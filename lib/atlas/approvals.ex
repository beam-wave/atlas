defmodule Atlas.Approvals do
  @moduledoc """
  The human approval gate, with its side effects:

    * approving an experiment design locks its thresholds;
    * rejecting one cancels the experiment;
    * every rejection reason is queued for the Analyst, which may propose
      skill edits (themselves approval items);
    * approving a skill edit appends it to the skill file.
  """
  require Logger

  alias Atlas.{Artifacts, Experiments}
  alias Atlas.Artifacts.Artifact
  alias Atlas.Skills.Library

  @experiment_kinds ~w(survey interview_guide smoke_test)

  def decide(artifact_id, decision, note, decided_by \\ "founder") do
    artifact = Artifacts.get!(artifact_id)

    Atlas.Repo.transaction(fn ->
      with {:ok, {updated, approval}} <- Artifacts.decide(artifact, decision, note, decided_by),
           :ok <- after_decision(updated, decision) do
        Atlas.Audit.log(updated.study_id, "artifact_#{decision}", %{
          artifact_id: updated.id,
          kind: updated.kind,
          note: note
        })

        {updated, approval}
      else
        {:error, reason} -> Atlas.Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, {updated, approval}} -> {:ok, updated, approval}
      error -> error
    end
  end

  defp after_decision(%Artifact{kind: kind, experiment_id: exp_id}, "approved")
       when kind in @experiment_kinds and not is_nil(exp_id) do
    with {:ok, _} <- Experiments.lock(Experiments.get!(exp_id)), do: :ok
  end

  defp after_decision(%Artifact{kind: kind, experiment_id: exp_id} = a, "rejected")
       when kind in @experiment_kinds and not is_nil(exp_id) do
    with {:ok, _} <- Experiments.cancel(Experiments.get!(exp_id)) do
      enqueue_analyst(a)
    end
  end

  defp after_decision(%Artifact{kind: "skill_edit_proposal"} = a, "approved"),
    do: apply_skill_edit(a)

  defp after_decision(%Artifact{} = a, "rejected"), do: enqueue_analyst(a)
  defp after_decision(_, _), do: :ok

  defp enqueue_analyst(%Artifact{kind: "skill_edit_proposal"}), do: :ok

  defp enqueue_analyst(%Artifact{study_id: study_id}) do
    %{study_id: study_id}
    |> Atlas.Workers.Analyst.new(schedule_in: 60)
    |> Oban.insert()
    |> case do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning("could not enqueue analyst: #{inspect(reason)}")
        :ok
    end
  end

  @doc "Appends an approved proposal to its skill under 'Lessons from reviews'."
  def apply_skill_edit(%Artifact{body: %{"skill" => name, "addition" => addition}}) do
    with {:ok, skill} <- Library.get(name),
         {:ok, content} <- File.read(skill.path) do
      heading = "## Lessons from reviews"

      updated =
        if String.contains?(content, heading),
          do: String.trim_trailing(content) <> "\n" <> String.trim(addition) <> "\n",
          else:
            String.trim_trailing(content) <>
              "\n\n" <> heading <> "\n\n" <> String.trim(addition) <> "\n"

      case Library.write(name, updated) do
        :ok -> :ok
        {:error, reason} -> {:error, {:skill_edit_failed, reason}}
      end
    else
      {:error, reason} -> {:error, {:skill_edit_failed, reason}}
    end
  end

  def apply_skill_edit(_), do: {:error, :malformed_proposal}
end
