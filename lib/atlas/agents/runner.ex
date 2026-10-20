defmodule Atlas.Agents.Runner do
  @moduledoc """
  Runs an agent: loads its skills, builds the prompt, calls the model, parses
  and validates the JSON output.

  Malformed output gets one retry with the validation errors attached; then
  the step fails visibly and is logged. `run_reviewed/4` adds the
  deterministic gates and the Skeptic review loop on top.
  """
  require Logger

  alias Atlas.Agents.{JSON, Skeptic}
  alias Atlas.Gates.{BannedPhrases, ClaimCheck}
  alias Atlas.LLM
  alias Atlas.LLM.Request
  alias Atlas.Skills.Library

  @max_attempts 2

  @type ctx :: %{
          optional(:study_id) => integer(),
          optional(:run_id) => String.t(),
          optional(atom()) => term()
        }

  @spec run(module(), map(), ctx()) :: {:ok, struct(), map()} | {:error, term()}
  def run(agent, input, ctx \\ %{}) do
    skills = Library.for_agent(agent.name(), agent.default_skills())
    system = system_prompt(agent, skills)
    prompt = agent.build_prompt(input) <> output_contract(agent)

    req = %Request{
      system: system,
      prompt: prompt,
      study_id: ctx[:study_id],
      agent: agent.name(),
      allow_web: agent.allow_web?(),
      metadata: %{agent: agent, input: input}
    }

    meta = %{skill_versions: Map.new(skills, &{&1.name, &1.hash}), attempts: 0}
    attempt(agent, input, req, ctx, meta, 1)
  end

  defp attempt(agent, input, req, ctx, meta, n) do
    meta = %{meta | attempts: n}

    with {:ok, resp} <- LLM.complete(req, llm_opts(ctx)),
         {:ok, raw} <- JSON.extract(resp.text),
         {:ok, output} <- cast(agent, raw),
         :ok <- agent.validate(output, input) do
      {:ok, output, meta}
    else
      {:error, {:invalid, errors}} when n < @max_attempts ->
        retry(agent, input, req, ctx, meta, n, errors)

      {:error, errors} when is_list(errors) and n < @max_attempts ->
        retry(agent, input, req, ctx, meta, n, errors)

      {:error, {:invalid, errors}} ->
        fail(agent, ctx, errors)

      {:error, errors} when is_list(errors) ->
        fail(agent, ctx, errors)

      {:error, reason} ->
        {:error, {:llm, reason}}
    end
  end

  defp retry(agent, input, req, ctx, meta, n, errors) do
    Logger.info("agent #{agent.name()} output invalid, retrying: #{inspect(errors)}")

    feedback = """


    ## Your previous reply was rejected

    It failed validation with these errors:
    #{Enum.map_join(errors, "\n", &"- #{&1}")}

    Reply again with the complete corrected JSON object only.
    """

    attempt(agent, input, %{req | prompt: req.prompt <> feedback}, ctx, meta, n + 1)
  end

  defp fail(agent, ctx, errors) do
    Atlas.Audit.log(ctx[:study_id], "agent_output_invalid", %{agent: agent.name(), errors: errors})

    {:error, {:invalid_output, agent.name(), errors}}
  end

  defp llm_opts(ctx), do: if(a = ctx[:adapter], do: [adapter: a], else: [])

  defp cast(agent, raw) when is_map(raw) do
    case agent.changeset(struct(agent), raw) |> Ecto.Changeset.apply_action(:validate) do
      {:ok, output} -> {:ok, output}
      {:error, cs} -> {:error, {:invalid, format_errors(cs)}}
    end
  end

  defp cast(_agent, _raw), do: {:error, {:invalid, ["reply must be a JSON object"]}}

  @doc "Flattens changeset errors (including nested embeds) into readable lines."
  def format_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> flatten_errors([])
  end

  defp flatten_errors(errors, path) when is_map(errors) do
    Enum.flat_map(errors, fn {k, v} -> flatten_errors(v, path ++ [to_string(k)]) end)
  end

  defp flatten_errors(errors, path) when is_list(errors) do
    errors
    |> Enum.with_index()
    |> Enum.flat_map(fn
      {msg, _i} when is_binary(msg) -> ["#{Enum.join(path, ".")} #{msg}"]
      {nested, i} when is_map(nested) -> flatten_errors(nested, path ++ ["[#{i}]"])
      _ -> []
    end)
  end

  ## Reviewed runs

  @doc """
  Runs a producer agent, then the deterministic gates, then the Skeptic.

  Options:
    * `:kind` — what is being reviewed (shown to the Skeptic)
    * `:evidence_ids` — `MapSet` of evidence ids; enables the claim check
    * `:evidence` — evidence digest shown to the Skeptic
    * `:banned_phrases` — run the banned-phrase gate (default false)
    * `:review` — run the Skeptic (default true)
    * `:max_revisions` — producer re-runs allowed after REVISE (default 1)

  Unreferenced claims block the output once revisions run out. A Skeptic
  REVISE after the last revision is kept and marked `review_verdict: "revise"`
  for the human approver.
  """
  def run_reviewed(agent, input, ctx, opts \\ []) do
    loop(agent, input, ctx, opts, Keyword.get(opts, :max_revisions, 1), [])
  end

  defp loop(agent, input, ctx, opts, revisions_left, history) do
    with {:ok, output, meta} <- run(agent, input, ctx) do
      output_map = to_map(output)

      case gate(output_map, opts) do
        {:block, issues} when revisions_left > 0 ->
          revise(agent, input, ctx, opts, revisions_left, history, "gate", issues)

        {:block, issues} ->
          Atlas.Audit.log(ctx[:study_id], "claim_check_blocked", %{
            agent: agent.name(),
            issues: issues
          })

          {:error, {:claim_check, agent.name(), issues}}

        {:warn, issues} when revisions_left > 0 ->
          revise(agent, input, ctx, opts, revisions_left, history, "gate", issues)

        gate_result ->
          gate_notes = if match?({:warn, _}, gate_result), do: elem(gate_result, 1), else: []

          review(
            agent,
            input,
            ctx,
            opts,
            revisions_left,
            history,
            output,
            output_map,
            meta,
            gate_notes
          )
      end
    end
  end

  defp review(
         agent,
         input,
         ctx,
         opts,
         revisions_left,
         history,
         output,
         output_map,
         meta,
         gate_notes
       ) do
    if Keyword.get(opts, :review, true) do
      skeptic_input = %{
        kind: opts[:kind] || agent.name(),
        output: output_map,
        evidence: opts[:evidence] || [],
        context: input[:review_context]
      }

      case run(Skeptic, skeptic_input, ctx) do
        {:ok, %{verdict: "PASS"} = r, _} ->
          finish(output, meta, "pass", history, gate_notes, r.issues)

        {:ok, %{verdict: "REVISE", issues: issues}, _} when revisions_left > 0 ->
          revise(
            agent,
            input,
            ctx,
            opts,
            revisions_left,
            history,
            "skeptic",
            Enum.map(issues, &issue_line/1)
          )

        {:ok, %{verdict: "REVISE"} = r, _} ->
          finish(output, meta, "revise", history, gate_notes, r.issues)

        {:error, reason} ->
          Logger.warning("skeptic failed: #{inspect(reason)}")

          finish(
            output,
            meta,
            "pending",
            history,
            ["skeptic review failed: #{inspect(reason)}" | gate_notes],
            []
          )
      end
    else
      finish(output, meta, "pending", history, gate_notes, [])
    end
  end

  defp revise(agent, input, ctx, opts, revisions_left, history, source, issues) do
    feedback = Map.get(input, :revision_feedback, []) ++ issues
    input = Map.put(input, :revision_feedback, feedback)

    loop(
      agent,
      input,
      ctx,
      opts,
      revisions_left - 1,
      history ++ [%{"source" => source, "issues" => issues}]
    )
  end

  defp finish(output, meta, verdict, history, gate_notes, issues) do
    notes = %{
      "issues" => Enum.map(issues, &to_map/1),
      "gate_notes" => gate_notes,
      "revisions" => history
    }

    {:ok, output, Map.merge(meta, %{review_verdict: verdict, review_notes: notes})}
  end

  defp issue_line(issue),
    do: "#{issue.kind}: #{issue.detail}#{if issue.fix, do: " Fix: #{issue.fix}", else: ""}"

  defp gate(output_map, opts) do
    claim =
      case opts[:evidence_ids] do
        nil -> :ok
        ids -> ClaimCheck.check(output_map, ids)
      end

    banned = if opts[:banned_phrases], do: BannedPhrases.check(output_map), else: :ok

    case {claim, banned} do
      {{:error, issues}, _} ->
        {:block, issues}

      {:ok, {:error, phrases}} ->
        {:warn, ["remove synthetic-sounding phrases: #{Enum.join(phrases, ", ")}"]}

      _ ->
        :ok
    end
  end

  ## Prompt pieces

  def system_prompt(agent, skills) do
    """
    You are the #{humanize(agent.name())} agent inside Atlas-PMF, a system that
    measures product-market fit from evidence. #{agent.role()}

    Ground rules:
    - Reply with a single JSON object and nothing else. No prose before or after it.
    - Never invent sources, numbers, quotes or customers. If you do not know, say so in the JSON or omit the item.
    - Every claim cites evidence IDs (like "E12") from the evidence you are given. Uncited claims are rejected by code.
    - Synthetic customers are never evidence. Desk research ranks hypotheses; only real customer behaviour establishes fit.

    # Skills

    #{Enum.map_join(skills, "\n\n", &"## Skill: #{&1.title} (#{&1.name}, v#{&1.version})\n\n#{&1.body}")}
    """
  end

  defp output_contract(agent) do
    """


    ## Output format

    Reply with JSON shaped exactly like this example (values are illustrative):

    ```json
    #{Jason.encode!(agent.output_example(), pretty: true)}
    ```
    """
  end

  defp humanize(name), do: name |> String.split("_") |> Enum.map_join(" ", &String.capitalize/1)

  @doc "Converts an output struct (with embeds) into a JSON-friendly map."
  def to_map(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  def to_map(%_{} = struct), do: struct |> Map.from_struct() |> Map.delete(:__meta__) |> to_map()
  def to_map(map) when is_map(map), do: Map.new(map, fn {k, v} -> {to_string(k), to_map(v)} end)
  def to_map(list) when is_list(list), do: Enum.map(list, &to_map/1)
  def to_map(other), do: other
end

defmodule Atlas.Agents.JSON do
  @moduledoc "Pulls the JSON object out of a model reply (bare, fenced, or with chatter around it)."

  def extract(text) when is_binary(text) do
    candidates =
      [fenced(text), String.trim(text), outer_object(text)]
      |> Enum.reject(&is_nil/1)

    Enum.find_value(
      candidates,
      {:error, {:invalid, ["reply did not contain a JSON object"]}},
      fn c ->
        case Jason.decode(c) do
          {:ok, %{} = map} -> {:ok, map}
          _ -> nil
        end
      end
    )
  end

  def extract(_), do: {:error, {:invalid, ["empty reply"]}}

  defp fenced(text) do
    case Regex.run(~r/```(?:json)?\s*\n(.*?)\n\s*```/s, text) do
      [_, body] -> body
      nil -> nil
    end
  end

  defp outer_object(text) do
    with start when is_integer(start) <- :binary.match(text, "{") |> pos(),
         stop when is_integer(stop) <- last_brace(text) do
      binary_part(text, start, stop - start + 1)
    else
      _ -> nil
    end
  end

  defp pos({start, _}), do: start
  defp pos(:nomatch), do: nil

  defp last_brace(text) do
    case :binary.matches(text, "}") do
      [] -> nil
      matches -> matches |> List.last() |> elem(0)
    end
  end
end
