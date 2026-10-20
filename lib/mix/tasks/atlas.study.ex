defmodule Mix.Tasks.Atlas.Study do
  @shortdoc "Runs a study from the terminal (no browser needed)"
  @moduledoc """
  Starts a study and drives it through the automatic steps, printing
  progress. Human steps (pruning, approvals, uploads) stay in the dashboard,
  unless you pass `--keep-all`, which keeps every proposed segment.

      mix atlas.study "AI bookkeeping for Indian freelancers" --name LedgerLite
      mix atlas.study "..." --adapter codex_cli --budget 80 --keep-all
      mix atlas.study "..." --adapter mock --keep-all   # offline demo, no model

  Stops when the study waits for a person (or fails) and prints where to go.
  """
  use Mix.Task

  @switches [
    name: :string,
    url: :string,
    price: :string,
    adapter: :string,
    budget: :integer,
    keep_all: :boolean,
    timeout: :integer
  ]

  @impl true
  def run(args) do
    {opts, rest, _} = OptionParser.parse(args, strict: @switches)

    description =
      case rest do
        [d | _] ->
          d

        [] ->
          Mix.raise(
            ~s(usage: mix atlas.study "product description" [--name NAME] [--adapter ADAPTER])
          )
      end

    Mix.Task.run("app.start")

    attrs = %{
      name: opts[:name] || description |> String.split() |> Enum.take(3) |> Enum.join(" "),
      description: description,
      url: opts[:url],
      price: opts[:price],
      adapter: opts[:adapter],
      budget: opts[:budget] || 150
    }

    case Atlas.Study.start(attrs) do
      {:ok, study} ->
        Mix.shell().info("Study #{study.id} started with #{Atlas.LLM.resolve_adapter(study.id)}.")
        Atlas.Studies.subscribe(study.id)

        follow(
          study.id,
          opts,
          System.monotonic_time(:millisecond) + (opts[:timeout] || 3_600) * 1000
        )

      {:error, %Ecto.Changeset{} = cs} ->
        Mix.raise("invalid study: #{inspect(Atlas.Agents.Runner.format_errors(cs))}")

      {:error, reason} ->
        Mix.raise("could not start: #{inspect(reason)}")
    end
  end

  defp follow(id, opts, deadline) do
    receive do
      {:study_event, ^id, {:running, state}} ->
        Mix.shell().info("  … #{state}")
        follow(id, opts, deadline)

      {:study_event, ^id, {:waiting, state}} ->
        waiting(id, state, opts, deadline)

      {:study_event, ^id, {:updated, %{state: "failed"}}} ->
        study = Atlas.Studies.get_study!(id)
        Mix.shell().error("Study failed in #{study.failed_state}: #{study.last_error}")

      {:study_event, ^id, {:updated, %{state: "await_data"}}} ->
        waiting(id, "await_data", opts, deadline)

      _ ->
        follow(id, opts, deadline)
    after
      max(deadline - System.monotonic_time(:millisecond), 0) -> Mix.shell().error("Timed out.")
    end
  end

  defp waiting(id, "hypothesize", opts, deadline) do
    segments = Atlas.Studies.list_segments(id, status: "proposed")
    Mix.shell().info("\nProposed segments:")

    for s <- segments,
        do: Mix.shell().info("  [#{s.id}] #{s.name} — #{s.job_to_be_done["functional"]}")

    if opts[:keep_all] do
      :ok = Atlas.Study.prune_segments(id, Enum.map(segments, & &1.id))
      Mix.shell().info("Kept all; starting desk research.")
      follow(id, opts, deadline)
    else
      done(id, "Prune segments in the dashboard (or rerun with --keep-all).")
    end
  end

  defp waiting(id, "await_data", _opts, _deadline) do
    study = Atlas.Studies.get_study!(id)
    card = Atlas.Artifacts.latest(id, "scorecard")

    if card do
      Mix.shell().info("\nDesk scorecard (verdict #{study.verdict}):")

      for s <- card.body["segments"] do
        Mix.shell().info(
          "  #{String.pad_trailing(s["name"], 40)} #{s["composite"] || "—"}  #{s["verdict"]}  next: #{s["next_move"]}"
        )
      end
    end

    done(id, "Approve the experiment designs, run them, and upload results in the dashboard.")
  end

  defp waiting(id, state, opts, deadline) do
    if state == "verdict",
      do: done(id, "Review the verdict in the dashboard."),
      else: follow(id, opts, deadline)
  end

  defp done(id, message) do
    Mix.shell().info(
      "\n#{message}\n  http://localhost:4000/studies/#{id}  (start the server with `mix phx.server`)"
    )
  end
end
