defmodule Atlas.Evidence.Observation do
  @moduledoc """
  One stored, cited fact. Facts are rows, never columns: a new signal needs no
  migration and every score is a query over observations.

  Its public evidence reference is `"E<id>"`. Signal codes are checked here
  and again by a foreign key on `signal_codes`, so a write that bypasses the
  changeset still fails loudly.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @evidence_types ~w(desk voc experimental)

  schema "observations" do
    field :signal_code, :string
    field :value_num, :float
    field :value_text, :string
    field :evidence_type, :string
    field :confidence, :float
    field :source_url, :string
    field :source_note, :string
    field :observed_at, :utc_datetime
    field :run_id, :string
    field :agent, :string
    field :loop_number, :integer, default: 1

    belongs_to :study, Atlas.Studies.Study
    belongs_to :segment, Atlas.Studies.Segment
    belongs_to :experiment, Atlas.Experiments.Experiment
    timestamps(type: :utc_datetime)
  end

  def evidence_types, do: @evidence_types

  def changeset(observation, attrs) do
    observation
    |> cast(attrs, [
      :study_id,
      :segment_id,
      :experiment_id,
      :signal_code,
      :value_num,
      :value_text,
      :evidence_type,
      :confidence,
      :source_url,
      :source_note,
      :observed_at,
      :run_id,
      :agent,
      :loop_number
    ])
    |> put_default_observed_at()
    |> validate_required([:study_id, :signal_code, :evidence_type, :confidence, :observed_at])
    |> validate_inclusion(:evidence_type, @evidence_types)
    |> validate_number(:confidence, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_value_present()
    |> validate_source()
    |> validate_length(:source_url, max: 2000)
    |> validate_inclusion(:signal_code, Atlas.Evidence.SignalCodes.codes(),
      message: "is not in the governed vocabulary"
    )
    |> assoc_constraint(:study)
  end

  defp put_default_observed_at(changeset) do
    if get_field(changeset, :observed_at),
      do: changeset,
      else: put_change(changeset, :observed_at, DateTime.utc_now(:second))
  end

  defp validate_value_present(changeset) do
    if is_nil(get_field(changeset, :value_num)) and blank?(get_field(changeset, :value_text)),
      do: add_error(changeset, :value_num, "either value_num or value_text is required"),
      else: changeset
  end

  # Desk and voice-of-customer evidence must say where it came from.
  defp validate_source(changeset) do
    type = get_field(changeset, :evidence_type)

    if type in ["desk", "voc"] and blank?(get_field(changeset, :source_url)) and
         blank?(get_field(changeset, :source_note)) do
      add_error(changeset, :source_url, "desk and voc evidence needs a source_url or source_note")
    else
      changeset
    end
  end

  defp blank?(v), do: v in [nil, ""] or (is_binary(v) and String.trim(v) == "")

  def ref(%__MODULE__{id: id}), do: "E#{id}"
  def ref(id) when is_integer(id), do: "E#{id}"

  def parse_ref("E" <> rest) do
    case Integer.parse(rest) do
      {id, ""} -> {:ok, id}
      _ -> :error
    end
  end

  def parse_ref(_), do: :error
end
