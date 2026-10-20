defmodule Atlas.Workers.Rescore do
  @moduledoc "Re-scores a study's active segments after new evidence arrives (e.g. re-observation)."
  use Oban.Worker, queue: :agents, max_attempts: 2, unique: [period: 300, keys: [:study_id]]

  alias Atlas.Study.Steps

  @impl true
  def perform(%Oban.Job{args: %{"study_id" => study_id}}) do
    case Atlas.Studies.get_study(study_id) do
      %{state: state} = study when state not in ["closed", "intake", "hypothesize"] ->
        case Steps.score_segments(
               study,
               %{study_id: study_id, run_id: "rescore-#{System.unique_integer([:positive])}"},
               "rescore"
             ) do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, reason}
        end

      _ ->
        {:cancel, :study_not_scorable}
    end
  end
end

defmodule Atlas.Workers.Reobserve do
  @moduledoc """
  Refreshes desk research for a study's active segments (markets move), then
  queues a re-score. Enqueue from the dashboard or on a schedule.
  """
  use Oban.Worker, queue: :agents, max_attempts: 2, unique: [period: 3600, keys: [:study_id]]

  alias Atlas.Agents.{MarketResearcher, Runner, VoCMiner}
  alias Atlas.{Evidence, Studies}
  alias Atlas.Study.Steps

  @impl true
  def perform(%Oban.Job{args: %{"study_id" => study_id}}) do
    with %{state: state} = study when state != "closed" <- Studies.get_study(study_id),
         [_ | _] = segments <- Steps.active_segments(study) do
      run_id = "reobserve-#{System.unique_integer([:positive])}"
      ctx = %{study_id: study_id, run_id: run_id}
      brief = (Atlas.Artifacts.latest(study_id, "brief") || %{body: %{}}).body

      stored =
        for seg <- segments, agent <- [MarketResearcher, VoCMiner] do
          input = %{
            brief: brief,
            segment: %{
              id: seg.id,
              name: seg.name,
              criteria: seg.criteria,
              job_to_be_done: seg.job_to_be_done
            }
          }

          with {:ok, out, _} <- Runner.run(agent, input, ctx) do
            type = if agent == VoCMiner, do: "voc", else: "desk"

            out.observations
            |> Enum.map(fn d ->
              %{
                study_id: study_id,
                segment_id: seg.id,
                signal_code: d.signal_code,
                value_num: d.value_num,
                value_text: d.value_text,
                evidence_type: type,
                confidence: d.confidence,
                source_url: d.source_url,
                source_note: d.source_note,
                run_id: run_id,
                agent: agent.name(),
                loop_number: study.loop_number
              }
            end)
            |> Evidence.record_many()
          end
        end

      if Enum.any?(stored, &match?({:ok, [_ | _]}, &1)) do
        %{study_id: study_id} |> Atlas.Workers.Rescore.new() |> Oban.insert()
      end

      :ok
    else
      _ -> {:cancel, :nothing_to_observe}
    end
  end
end

defmodule Atlas.Workers.Reminder do
  @moduledoc """
  Daily nudge for studies waiting on people: approved experiments with no
  results after `:reminder_after_days` (default 7), and approvals sitting in
  the queue. Reminders go to the audit log and the dashboard via PubSub.
  """
  use Oban.Worker, queue: :default, max_attempts: 1

  alias Atlas.{Artifacts, Experiments, Studies}

  @impl true
  def perform(_job) do
    days = Application.get_env(:atlas, :reminder_after_days, 7)
    cutoff = DateTime.add(DateTime.utc_now(), -days * 86_400, :second)

    for study <- Studies.list_studies(), study.state == "await_data" do
      stale =
        for e <- Experiments.list(study.id, status: "locked"),
            e.results == [],
            e.locked_at && DateTime.compare(e.locked_at, cutoff) == :lt,
            do: e.title

      pending = Artifacts.pending_count(study.id)

      if stale != [] or pending > 0 do
        payload = %{experiments_without_results: stale, pending_approvals: pending}
        Atlas.Audit.log(study.id, "reminder", payload)
        Studies.broadcast(study.id, {:reminder, payload})
      end
    end

    :ok
  end
end

defmodule Atlas.Workers.Analyst do
  @moduledoc """
  Reads recent rejection notes and asks the Analyst agent for skill edits.
  Each proposal becomes a `skill_edit_proposal` artifact in the approval
  queue; nothing changes until a person approves it.
  """
  use Oban.Worker, queue: :agents, max_attempts: 2, unique: [period: 600, keys: [:study_id]]

  alias Atlas.Agents.{Analyst, Runner}
  alias Atlas.Artifacts
  alias Atlas.Skills.Library

  @min_notes 2

  @impl true
  def perform(%Oban.Job{args: %{"study_id" => study_id}}) do
    notes = Artifacts.rejection_notes(limit: 20)

    if length(notes) < @min_notes do
      {:cancel, :not_enough_notes}
    else
      input = %{
        rejections: Enum.map(notes, &Map.new(&1, fn {k, v} -> {to_string(k), v} end)),
        skills: Enum.map(Library.all(), &%{"name" => &1.name, "description" => &1.description})
      }

      case Runner.run(Analyst, input, %{study_id: study_id}) do
        {:ok, out, meta} ->
          for p <- out.proposals do
            Artifacts.create(%{
              study_id: study_id,
              kind: "skill_edit_proposal",
              agent: "analyst",
              body: Runner.to_map(p),
              skill_versions: meta.skill_versions
            })
          end

          :ok

        {:error, reason} ->
          {:error, reason}
      end
    end
  end
end
