defmodule Atlas.Studies.Segment do
  @moduledoc "A candidate customer segment with its job to be done."
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(proposed kept pruned)

  schema "segments" do
    field :name, :string
    field :criteria, :map, default: %{}
    field :job_to_be_done, :map, default: %{}
    field :rationale, :string
    field :status, :string, default: "proposed"
    field :rank, :integer
    field :loop_number, :integer, default: 1

    belongs_to :study, Atlas.Studies.Study
    has_many :hypotheses, Atlas.Studies.Hypothesis
    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  def changeset(segment, attrs) do
    segment
    |> cast(attrs, [
      :study_id,
      :name,
      :criteria,
      :job_to_be_done,
      :rationale,
      :status,
      :rank,
      :loop_number
    ])
    |> validate_required([:study_id, :name])
    |> validate_inclusion(:status, @statuses)
    |> assoc_constraint(:study)
  end
end
