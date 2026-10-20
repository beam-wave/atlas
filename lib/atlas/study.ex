defmodule Atlas.Study do
  @moduledoc """
  Public API for running studies. Everything a person does to a study goes
  through here (or `Atlas.Approvals` for the approval queue).
  """
  alias Atlas.Study.{Coordinator, Supervisor}
  alias Atlas.Studies

  @doc """
  Creates a product and its study, then starts the coordinator.

      Atlas.Study.start(%{name: "LedgerLite", description: "...", url: "https://...", budget: 150, adapter: "claude_cli"})
  """
  def start(attrs) do
    with {:ok, study} <- Studies.create_study(attrs),
         {:ok, _pid} <- Supervisor.ensure_started(study.id) do
      Atlas.Audit.log(study.id, "study_started", %{adapter: Atlas.LLM.resolve_adapter(study.id)})
      {:ok, study}
    end
  end

  @doc "Starts coordinators for every study that is not closed (used at boot)."
  def resume_all do
    for id <- Studies.list_active_study_ids(), do: Supervisor.ensure_started(id)
  end

  def prune_segments(study_id, keep_ids), do: send_event(study_id, {:prune, keep_ids})
  def finish_data_collection(study_id), do: send_event(study_id, :finish_data)

  @doc "Starts the next loop. `route` defaults to what the verdict's next move implies."
  def continue(study_id, route \\ nil), do: send_event(study_id, {:continue, route})

  def retry(study_id), do: send_event(study_id, :retry)
  def close(study_id), do: send_event(study_id, :close)

  @doc "Re-runs the current automatic step (e.g. after releasing the kill switch)."
  def wake(study_id), do: send_event(study_id, :wake)

  def status(study_id) do
    with {:ok, _} <- Supervisor.ensure_started(study_id), do: Coordinator.status(study_id)
  end

  def running?(study_id), do: Supervisor.running?(study_id)

  @doc "Deletes a study, its evidence and uploads (privacy: per-study deletion)."
  def delete(study_id) do
    Supervisor.stop(study_id)
    Atlas.Experiments.delete_uploads(study_id)
    study = Studies.get_study!(study_id)
    Atlas.Repo.delete(study.product)
  end

  defp send_event(study_id, event) do
    with {:ok, _pid} <- ensure_open(study_id) do
      Coordinator.event(study_id, event)
    end
  end

  defp ensure_open(study_id) do
    case Studies.get_study(study_id) do
      nil -> {:error, :not_found}
      %{state: "closed"} -> {:error, :closed}
      _ -> Supervisor.ensure_started(study_id)
    end
  end
end
