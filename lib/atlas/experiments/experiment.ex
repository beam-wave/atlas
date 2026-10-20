defmodule Atlas.Experiments.Experiment do
  @moduledoc """
  A cheap test of one hypothesis. Thresholds are stored as
  `%{"criteria" => [%{"metric", "operator", "value"}], "min_sample" => n}` and
  become immutable once `locked_at` is set.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @kinds ~w(survey interview smoke_test)
  @statuses ~w(draft locked completed cancelled)
  @outcomes ~w(passed failed inconclusive)

  schema "experiments" do
    field :kind, :string
    field :title, :string
    field :design, :map, default: %{}
    field :thresholds, :map, default: %{}
    field :locked_at, :utc_datetime
    field :status, :string, default: "draft"
    field :outcome, :string
    field :loop_number, :integer, default: 1

    belongs_to :study, Atlas.Studies.Study
    belongs_to :hypothesis, Atlas.Studies.Hypothesis
    belongs_to :segment, Atlas.Studies.Segment
    has_many :results, Atlas.Experiments.Result
    timestamps(type: :utc_datetime)
  end

  def kinds, do: @kinds
  def outcomes, do: @outcomes

  def create_changeset(experiment, attrs) do
    experiment
    |> cast(attrs, [
      :study_id,
      :hypothesis_id,
      :segment_id,
      :kind,
      :title,
      :design,
      :thresholds,
      :loop_number
    ])
    |> validate_required([:study_id, :kind, :title, :thresholds])
    |> validate_inclusion(:kind, @kinds)
    |> validate_thresholds()
  end

  @doc "Changes to an unlocked experiment's design or thresholds."
  def edit_changeset(experiment, attrs) do
    experiment
    |> cast(attrs, [:title, :design, :thresholds])
    |> validate_thresholds()
  end

  def status_changeset(experiment, attrs) do
    experiment
    |> cast(attrs, [:status, :outcome, :locked_at])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:outcome, @outcomes)
  end

  @operators ~w(>= > <= < ==)

  def operators, do: @operators

  defp validate_thresholds(changeset) do
    validate_change(changeset, :thresholds, fn :thresholds, thresholds ->
      criteria = thresholds["criteria"] || thresholds[:criteria]

      cond do
        not is_list(criteria) or criteria == [] ->
          [thresholds: "needs at least one criterion"]

        not Enum.all?(criteria, &valid_criterion?/1) ->
          [
            thresholds:
              "each criterion needs a metric, an operator (#{Enum.join(@operators, " ")}) and a numeric value"
          ]

        true ->
          []
      end
    end)
  end

  defp valid_criterion?(c) when is_map(c) do
    metric = c["metric"] || c[:metric]
    op = c["operator"] || c[:operator]
    value = c["value"] || c[:value]
    is_binary(metric) and metric != "" and op in @operators and is_number(value)
  end

  defp valid_criterion?(_), do: false
end
