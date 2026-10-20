defmodule Atlas.Artifacts.Artifact do
  @moduledoc """
  A document an agent produced: brief, positioning, survey, scorecard and so
  on. Kinds that leave the building (anything a person will send or publish)
  need explicit approval.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @kinds ~w(brief segments research competitor_map positioning survey interview_guide smoke_test scorecard skill_edit_proposal)
  @approval_kinds ~w(positioning survey interview_guide smoke_test skill_edit_proposal)
  @statuses ~w(final pending_approval approved rejected)
  @review_verdicts ~w(pending pass revise)

  schema "artifacts" do
    field :kind, :string
    field :agent, :string
    field :loop_number, :integer, default: 1
    field :body, :map, default: %{}
    field :review_verdict, :string, default: "pending"
    field :review_notes, :map, default: %{}
    field :status, :string, default: "final"
    field :skill_versions, :map, default: %{}

    belongs_to :study, Atlas.Studies.Study
    belongs_to :segment, Atlas.Studies.Segment
    belongs_to :experiment, Atlas.Experiments.Experiment
    has_many :approvals, Atlas.Artifacts.Approval
    timestamps(type: :utc_datetime)
  end

  def kinds, do: @kinds
  def approval_kinds, do: @approval_kinds
  def needs_approval?(kind), do: kind in @approval_kinds

  def changeset(artifact, attrs) do
    artifact
    |> cast(attrs, [
      :study_id,
      :segment_id,
      :experiment_id,
      :kind,
      :agent,
      :loop_number,
      :body,
      :review_verdict,
      :review_notes,
      :status,
      :skill_versions
    ])
    |> validate_required([:study_id, :kind, :body])
    |> validate_inclusion(:kind, @kinds)
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:review_verdict, @review_verdicts)
    |> put_default_status()
    |> assoc_constraint(:study)
  end

  defp put_default_status(changeset) do
    if changeset.data.id == nil and get_change(changeset, :status) == nil and
         needs_approval?(get_field(changeset, :kind)) do
      put_change(changeset, :status, "pending_approval")
    else
      changeset
    end
  end
end
