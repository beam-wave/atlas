defmodule Atlas.Artifacts.Approval do
  @moduledoc "A person's decision on an artifact, with the reason."
  use Ecto.Schema
  import Ecto.Changeset

  schema "approvals" do
    field :decision, :string
    field :note, :string
    field :decided_by, :string
    field :decided_at, :utc_datetime

    belongs_to :artifact, Atlas.Artifacts.Artifact
    timestamps(type: :utc_datetime)
  end

  def changeset(approval, attrs) do
    approval
    |> cast(attrs, [:artifact_id, :decision, :note, :decided_by, :decided_at])
    |> validate_required([:artifact_id, :decision, :decided_by, :decided_at])
    |> validate_inclusion(:decision, ~w(approved rejected))
    |> validate_rejection_note()
  end

  # A rejection without a reason teaches the system nothing.
  defp validate_rejection_note(changeset) do
    if get_field(changeset, :decision) == "rejected" and
         String.trim(get_field(changeset, :note) || "") == "" do
      add_error(changeset, :note, "is required when rejecting")
    else
      changeset
    end
  end
end
