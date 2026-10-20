defmodule Atlas.Experiments.Result do
  @moduledoc "An uploaded result (survey CSV, transcript, analytics export) for an experiment."
  use Ecto.Schema
  import Ecto.Changeset

  @kinds ~w(survey_csv transcript analytics_csv retention_csv)

  schema "experiment_results" do
    field :kind, :string
    field :raw_upload_ref, :string
    field :summary, :map, default: %{}
    field :ingested_at, :utc_datetime

    belongs_to :experiment, Atlas.Experiments.Experiment
    timestamps(type: :utc_datetime)
  end

  def kinds, do: @kinds

  def changeset(result, attrs) do
    result
    |> cast(attrs, [:experiment_id, :kind, :raw_upload_ref, :summary, :ingested_at])
    |> validate_required([:experiment_id, :kind])
    |> validate_inclusion(:kind, @kinds)
    |> assoc_constraint(:experiment)
  end
end
