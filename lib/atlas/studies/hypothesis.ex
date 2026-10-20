defmodule Atlas.Studies.Hypothesis do
  @moduledoc "A falsifiable statement about a segment."
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(open supported falsified)

  schema "hypotheses" do
    field :statement, :string
    field :falsified_if, :string
    field :status, :string, default: "open"

    belongs_to :study, Atlas.Studies.Study
    belongs_to :segment, Atlas.Studies.Segment
    timestamps(type: :utc_datetime)
  end

  def changeset(hypothesis, attrs) do
    hypothesis
    |> cast(attrs, [:study_id, :segment_id, :statement, :falsified_if, :status])
    |> validate_required([:study_id, :segment_id, :statement, :falsified_if])
    |> validate_inclusion(:status, @statuses)
    |> assoc_constraint(:segment)
  end
end
