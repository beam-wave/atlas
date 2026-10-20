defmodule Atlas.Experiments do
  @moduledoc """
  Experiments, threshold locking and result uploads.

  Thresholds lock when the experiment's design is approved (or explicitly via
  `lock/1`). Results can only be uploaded to a locked experiment, and any edit
  after locking is refused and written to the audit log.
  """
  import Ecto.Query

  alias Atlas.Experiments.{Experiment, Result}
  alias Atlas.Gates
  alias Atlas.Repo

  def create(attrs) do
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)

    with :ok <- lint(attrs["kind"], attrs["design"]) do
      %Experiment{} |> Experiment.create_changeset(attrs) |> Repo.insert()
    end
  end

  defp lint("survey", design), do: Gates.SurveyLint.check(design || %{})
  defp lint(_kind, _design), do: :ok

  def get!(id), do: Repo.get!(Experiment, id)

  def list(study_id, opts \\ []) do
    Experiment
    |> where([e], e.study_id == ^study_id)
    |> then(fn q ->
      if s = opts[:status], do: where(q, [e], e.status in ^List.wrap(s)), else: q
    end)
    |> then(fn q -> if l = opts[:loop], do: where(q, [e], e.loop_number == ^l), else: q end)
    |> order_by(asc: :id)
    |> preload(:results)
    |> Repo.all()
  end

  @doc "Edits an experiment. Refused (and logged) once thresholds are locked."
  def edit(%Experiment{} = experiment, attrs) do
    with :ok <- Gates.ThresholdLock.check_edit(experiment, attrs) do
      kind = experiment.kind
      design = attrs["design"] || attrs[:design]

      with :ok <- if(design, do: lint(kind, design), else: :ok) do
        experiment |> Experiment.edit_changeset(attrs) |> Repo.update()
      end
    end
  end

  def lock(%Experiment{locked_at: nil} = experiment) do
    {:ok, locked} =
      experiment
      |> Experiment.status_changeset(%{status: "locked", locked_at: DateTime.utc_now(:second)})
      |> Repo.update()

    Atlas.Audit.log(experiment.study_id, "thresholds_locked", %{
      experiment_id: experiment.id,
      thresholds: experiment.thresholds
    })

    {:ok, locked}
  end

  def lock(%Experiment{} = experiment), do: {:ok, experiment}

  def cancel(%Experiment{} = experiment) do
    experiment |> Experiment.status_changeset(%{status: "cancelled"}) |> Repo.update()
  end

  def complete(%Experiment{} = experiment, outcome) do
    experiment
    |> Experiment.status_changeset(%{status: "completed", outcome: outcome})
    |> Repo.update()
  end

  @doc """
  Stores and parses an uploaded result file for a locked experiment.

  `kind` is one of #{inspect(Result.kinds())}. The raw file is copied into the
  uploads directory; transcripts are stored redacted.
  """
  def upload_result(%Experiment{} = experiment, kind, source_path, opts \\ []) do
    with :ok <- Gates.ThresholdLock.check_upload(experiment),
         {:ok, summary, stored_body} <- Atlas.Ingest.parse(kind, source_path),
         {:ok, ref} <-
           store_upload(
             experiment,
             kind,
             stored_body,
             opts[:filename] || Path.basename(source_path)
           ),
         {:ok, result} <-
           %Result{}
           |> Result.changeset(%{
             experiment_id: experiment.id,
             kind: kind,
             raw_upload_ref: ref,
             summary: summary,
             ingested_at: DateTime.utc_now(:second)
           })
           |> Repo.insert() do
      Atlas.Audit.log(experiment.study_id, "result_uploaded", %{
        experiment_id: experiment.id,
        kind: kind
      })

      Atlas.Studies.broadcast(experiment.study_id, {:result_uploaded, experiment.id})
      {:ok, result}
    end
  end

  def list_results(experiment_id) do
    Result |> where([r], r.experiment_id == ^experiment_id) |> order_by(asc: :id) |> Repo.all()
  end

  def read_upload(%Result{raw_upload_ref: ref}), do: File.read(Path.join(uploads_dir(), ref))

  def uploads_dir do
    Application.get_env(:atlas, :uploads_dir) || Path.expand("uploads", File.cwd!())
  end

  defp store_upload(experiment, kind, body, filename) do
    safe = filename |> Path.basename() |> String.replace(~r/[^A-Za-z0-9._-]/, "_")

    rel =
      Path.join([
        "study_#{experiment.study_id}",
        "exp_#{experiment.id}",
        "#{System.unique_integer([:positive])}_#{kind}_#{safe}"
      ])

    path = Path.join(uploads_dir(), rel)

    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(path, body) do
      {:ok, rel}
    end
  end

  @doc "Deletes stored uploads for a study (per-study deletion)."
  def delete_uploads(study_id), do: File.rm_rf(Path.join(uploads_dir(), "study_#{study_id}"))
end
