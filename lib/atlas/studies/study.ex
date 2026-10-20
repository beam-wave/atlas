defmodule Atlas.Studies.Study do
  @moduledoc """
  One product evaluation. Moves through the eight lifecycle states and loops
  until a verdict is reached.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @states ~w(intake hypothesize desk_research desk_score design_tests await_data ingest_results verdict closed failed)
  @verdicts ~w(no_signal promising approaching_fit fit)
  @next_moves ~w(double_down narrow reposition pivot)

  # States where the study waits for a person rather than running agents.
  @human_states ~w(hypothesize await_data verdict)

  schema "studies" do
    field :state, :string, default: "intake"
    field :loop_number, :integer, default: 1
    field :budget, :integer, default: 150
    field :calls_used, :integer, default: 0
    field :verdict, :string
    field :next_move, :string
    field :adapter, :string
    field :last_error, :string
    field :failed_state, :string

    belongs_to :product, Atlas.Studies.Product
    has_many :segments, Atlas.Studies.Segment
    has_many :experiments, Atlas.Experiments.Experiment
    has_many :artifacts, Atlas.Artifacts.Artifact
    timestamps(type: :utc_datetime)
  end

  def states, do: @states
  def verdicts, do: @verdicts
  def next_moves, do: @next_moves
  def human_states, do: @human_states

  def create_changeset(study, attrs) do
    study
    |> cast(attrs, [:product_id, :budget, :adapter])
    |> validate_required([:product_id])
    |> validate_number(:budget, greater_than: 0, less_than_or_equal_to: 10_000)
    |> validate_adapter()
    |> assoc_constraint(:product)
  end

  def update_changeset(study, attrs) do
    study
    |> cast(attrs, [
      :state,
      :loop_number,
      :verdict,
      :next_move,
      :last_error,
      :failed_state,
      :budget,
      :adapter
    ])
    |> validate_inclusion(:state, @states)
    |> validate_inclusion(:verdict, @verdicts)
    |> validate_inclusion(:next_move, @next_moves)
    |> validate_number(:budget, greater_than: 0)
    |> validate_adapter()
  end

  defp validate_adapter(changeset) do
    validate_change(changeset, :adapter, fn :adapter, value ->
      if value in Atlas.LLM.adapter_names(), do: [], else: [adapter: "is not a known adapter"]
    end)
  end
end
