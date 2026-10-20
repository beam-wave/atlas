defmodule Atlas.Gates do
  @moduledoc """
  Deterministic checks. No model is involved in any of them.

  1. `ClaimCheck` — every claim cites an evidence ID that exists.
  2. `ThresholdLock` — thresholds cannot change after locking; results need a lock.
  3. `SurveyLint` — no leading, double-barrelled or hypothetical-future questions.
  4. `VerdictGuard` — no Approaching fit / Fit without experimental evidence.
  5. `Outbound` — nothing leaves without explicit approval.
  6. Budget and kill switch live in `Atlas.LLM.RateLimiter`.

  Plus `BannedPhrases`, which asks for a rewrite of synthetic-sounding copy.
  """
end

defmodule Atlas.Gates.ClaimCheck do
  @moduledoc """
  Every claim must reference at least one evidence ID (`"E12"`) that exists
  for the study. Claims are found anywhere in an output under a `"claims"`
  key, as `%{"text" => ..., "evidence_ids" => [...]}`.
  """
  alias Atlas.Evidence.Observation

  @spec check(map() | list(), MapSet.t()) :: :ok | {:error, [String.t()]}
  def check(output, known_ids) do
    issues =
      output
      |> collect_claims()
      |> Enum.flat_map(&claim_issues(&1, known_ids))

    if issues == [], do: :ok, else: {:error, issues}
  end

  defp claim_issues(%{"text" => text} = claim, known_ids) do
    refs = List.wrap(claim["evidence_ids"])

    cond do
      refs == [] ->
        ["uncited claim: #{short(text)}"]

      true ->
        for ref <- refs, not known?(ref, known_ids) do
          "claim cites #{inspect(ref)}, which is not in this study's evidence: #{short(text)}"
        end
    end
  end

  defp claim_issues(other, _), do: ["malformed claim: #{inspect(other) |> short()}"]

  defp known?(ref, known_ids) do
    case Observation.parse_ref(to_string(ref)) do
      {:ok, id} -> MapSet.member?(known_ids, id)
      :error -> false
    end
  end

  @doc "All claim maps found anywhere in a nested output."
  def collect_claims(%_{} = struct), do: struct |> Map.from_struct() |> collect_claims()

  def collect_claims(map) when is_map(map) do
    Enum.flat_map(map, fn
      {k, claims} when k in ["claims", :claims] and is_list(claims) ->
        Enum.map(claims, &stringify/1)

      {_k, v} ->
        collect_claims(v)
    end)
  end

  def collect_claims(list) when is_list(list), do: Enum.flat_map(list, &collect_claims/1)
  def collect_claims(_), do: []

  defp stringify(%_{} = s), do: s |> Map.from_struct() |> stringify()
  defp stringify(m) when is_map(m), do: Map.new(m, fn {k, v} -> {to_string(k), v} end)
  defp stringify(other), do: other

  defp short(text), do: text |> to_string() |> String.slice(0, 120)
end

defmodule Atlas.Gates.SurveyLint do
  @moduledoc """
  Rejects leading, double-barrelled and hypothetical-future questions.

  The standard Sean Ellis question and the four Van Westendorp questions use
  "would" by design; questions typed `sean_ellis` or `van_westendorp` are
  exempt from the hypothetical check.
  """

  @leading [
    ~r/\b(don't|doesn't|wouldn't|isn't|aren't|won't) you\b/i,
    ~r/\bagree that\b/i,
    ~r/\bhow (much|great|amazing|useful|helpful) (do|would|is|was)\b.*\b(love|enjoy|like)\b/i,
    ~r/\bhow (great|amazing|easy|helpful|useful) (is|was|would)\b/i,
    ~r/\b(obviously|clearly|surely)\b/i
  ]

  @hypothetical [
    ~r/\bwould you\b/i,
    ~r/\bwill you\b/i,
    ~r/\bif (we|there) (built|build|made|make|offered|offer|launched|launch)\b/i,
    ~r/\bimagine\b/i,
    ~r/\bin the future\b/i,
    ~r/\bwould (it|this) be\b/i
  ]

  @single_answer_types ~w(rating scale yes_no likert nps)
  @exempt_types ~w(sean_ellis van_westendorp)

  @spec check(map()) :: :ok | {:error, {:survey_lint, [map()]}}
  def check(design) do
    questions = design["questions"] || design[:questions] || []

    issues =
      if questions == [] do
        [%{"question" => nil, "issue" => "survey has no questions"}]
      else
        questions |> Enum.with_index(1) |> Enum.flat_map(&question_issues/1)
      end

    if issues == [], do: :ok, else: {:error, {:survey_lint, issues}}
  end

  defp question_issues({q, n}) do
    text = to_string(q["text"] || q[:text] || "")
    type = to_string(q["type"] || q[:type] || "open")

    [
      if(String.trim(text) == "", do: "empty question"),
      if(Enum.any?(@leading, &Regex.match?(&1, text)), do: "leading question"),
      if(type not in @exempt_types and Enum.any?(@hypothetical, &Regex.match?(&1, text)),
        do: "hypothetical-future question (ask about past behaviour instead)"
      ),
      if(type in @single_answer_types and double_barrelled?(text),
        do: "double-barrelled question (asks about two things with one answer)"
      )
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&%{"question" => n, "text" => text, "issue" => &1})
  end

  defp double_barrelled?(text) do
    Regex.match?(~r/\b\w+\s+(and|or)\s+\w+/i, text) and
      not Regex.match?(~r/\b(more or less|and so on|or not)\b/i, text)
  end
end

defmodule Atlas.Gates.ThresholdLock do
  @moduledoc """
  Success criteria are fixed before data arrives. Edits after locking are
  refused and logged; uploads need a locked experiment.
  """
  alias Atlas.Experiments.Experiment

  def check_edit(%Experiment{locked_at: nil}, _attrs), do: :ok

  def check_edit(%Experiment{} = exp, attrs) do
    touched = attrs |> Map.keys() |> Enum.map(&to_string/1)

    if Enum.any?(touched, &(&1 in ["thresholds", "design"])) do
      Atlas.Audit.log(exp.study_id, "threshold_edit_refused", %{
        experiment_id: exp.id,
        attempted: Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
      })

      {:error, :thresholds_locked}
    else
      :ok
    end
  end

  def check_upload(%Experiment{status: "locked", locked_at: %DateTime{}}), do: :ok
  def check_upload(%Experiment{status: "completed"}), do: {:error, :experiment_completed}
  def check_upload(%Experiment{status: "cancelled"}), do: {:error, :experiment_cancelled}
  def check_upload(%Experiment{}), do: {:error, :not_locked}
end

defmodule Atlas.Gates.VerdictGuard do
  @moduledoc """
  `approaching_fit` and `fit` are only reachable with experimental evidence.
  Without it the verdict is capped at `promising`.
  """
  @strong ~w(approaching_fit fit)

  @spec apply(String.t(), [String.t()]) :: {String.t(), String.t() | nil}
  def apply(verdict, evidence_types) do
    if verdict in @strong and "experimental" not in evidence_types do
      {"promising", "capped at promising: #{verdict} needs experimental evidence"}
    else
      {verdict, nil}
    end
  end
end

defmodule Atlas.Gates.BannedPhrases do
  @moduledoc """
  Flags synthetic-sounding phrases. The list lives in the `clear_writing`
  skill under `### Banned phrases`, so it is editable without code.
  """
  alias Atlas.Skills.{Library, Skill}

  def phrases do
    case Library.get("clear_writing") do
      {:ok, skill} -> Skill.bullets_under(skill, "Banned phrases")
      _ -> []
    end
  end

  @spec check(term(), [String.t()]) :: :ok | {:error, [String.t()]}
  def check(output, phrases \\ phrases()) do
    text = output |> strings() |> Enum.join("\n") |> String.downcase()

    found =
      Enum.filter(phrases, fn phrase ->
        Regex.match?(~r/(^|[^a-z])#{Regex.escape(String.downcase(phrase))}([^a-z]|$)/u, text)
      end)

    if found == [], do: :ok, else: {:error, found}
  end

  defp strings(%_{} = s), do: s |> Map.from_struct() |> strings()
  defp strings(m) when is_map(m), do: m |> Map.values() |> Enum.flat_map(&strings/1)
  defp strings(l) when is_list(l), do: Enum.flat_map(l, &strings/1)
  defp strings(s) when is_binary(s), do: [s]
  defp strings(_), do: []
end

defmodule Atlas.Gates.Outbound do
  @moduledoc """
  Nothing is sent, published or posted without explicit approval. Every
  export of an approval-kind artifact goes through `authorize/1`.
  """
  alias Atlas.Artifacts.Artifact

  def authorize(%Artifact{kind: kind, status: status} = artifact) do
    cond do
      not Artifact.needs_approval?(kind) ->
        :ok

      status == "approved" ->
        :ok

      true ->
        Atlas.Audit.log(artifact.study_id, "outbound_refused", %{
          artifact_id: artifact.id,
          status: status
        })

        {:error, :not_approved}
    end
  end
end
