defmodule Atlas.Agents.PMFScorer do
  @moduledoc """
  Proposes dimension ratings for one segment, citing evidence, and suggests
  the next experiment. `Atlas.Scoring` then recomputes evidence types,
  composite, verdict and next move deterministically.
  """
  use Atlas.Agents.Agent,
    name: "pmf_scorer",
    skills: ~w(guardrails pmf_scorecard decision_frameworks pivot_patterns retention_signals)

  alias Atlas.Agents.Schemas.Claim

  @dimensions ~w(problem_intensity willingness_to_pay reachability competitive_gap)

  defmodule Rating do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset
    @primary_key false
    embedded_schema do
      field :dimension, :string
      field :score, :float
      field :evidence_type, :string
      field :evidence_ids, {:array, :string}, default: []
      field :rationale, :string
    end

    def changeset(r, attrs) do
      r
      |> cast(attrs, [:dimension, :score, :evidence_type, :evidence_ids, :rationale])
      |> validate_required([:dimension, :score, :rationale])
      |> validate_number(:score, greater_than_or_equal_to: 0, less_than_or_equal_to: 5)
    end
  end

  embedded_schema do
    field :summary, :string
    field :next_move_suggestion, :string
    field :next_experiment, :string
    embeds_many :ratings, Rating
    embeds_many :claims, Claim
  end

  @impl true
  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [:summary, :next_move_suggestion, :next_experiment])
    |> validate_required([:summary, :next_experiment])
    |> validate_inclusion(:next_move_suggestion, Atlas.Studies.Study.next_moves())
    |> cast_embed(:ratings)
    |> cast_embed(:claims)
  end

  @impl true
  def validate(out, _input) do
    bad = out.ratings |> Enum.map(& &1.dimension) |> Enum.reject(&(&1 in @dimensions))

    cond do
      bad != [] ->
        {:error,
         [
           "rate only #{Enum.join(@dimensions, ", ")}; sean_ellis and retention are computed by code (got #{Enum.join(bad, ", ")})"
         ]}

      Enum.any?(out.ratings, &(&1.evidence_ids == [])) ->
        {:error,
         ["every rating cites at least one evidence ID; leave a dimension out rather than guess"]}

      true ->
        :ok
    end
  end

  @impl true
  def role do
    "You score one segment against the PMF rubric. You rate only what the evidence supports, cite it, " <>
      "and name the single experiment that would most change the verdict."
  end

  @impl true
  def build_prompt(input) do
    """
    Rate this segment on #{Enum.join(@dimensions, ", ")} (0–5 each). Skip a dimension if no
    evidence supports a rating. Cite evidence IDs for every rating. Sean Ellis and retention
    are computed from uploads by code: do not rate them. Suggest a next move
    (double_down, narrow, reposition, pivot) and the one experiment that would most change
    the verdict.

    #{section("Product brief", input[:brief])}#{section("Segment", input[:segment])}#{section("Evidence", input[:evidence])}#{section("Experiment results", input[:results])}#{feedback(input)}
    """
  end

  @impl true
  def output_example do
    %{
      "summary" => "Strong, frequent pain; price tolerance unproven",
      "ratings" => [
        %{
          "dimension" => "problem_intensity",
          "score" => 4,
          "evidence_type" => "voc",
          "evidence_ids" => ["E3", "E7"],
          "rationale" => "Quarterly pain, weekend-long workaround"
        }
      ],
      "next_move_suggestion" => "narrow",
      "next_experiment" => "Van Westendorp survey with 60 GST-registered designers",
      "claims" => [
        %{"text" => "Designers describe losing a weekend each quarter", "evidence_ids" => ["E3"]}
      ]
    }
  end

  @impl true
  def mock_output(input) do
    refs = Atlas.Agents.Mock.refs(input[:evidence], 3)

    ratings =
      if refs == [] do
        []
      else
        [
          %{
            "dimension" => "problem_intensity",
            "score" => 3,
            "evidence_type" => "voc",
            "evidence_ids" => refs,
            "rationale" => "Mock rating"
          },
          %{
            "dimension" => "reachability",
            "score" => 3,
            "evidence_type" => "desk",
            "evidence_ids" => refs,
            "rationale" => "Mock rating"
          },
          %{
            "dimension" => "competitive_gap",
            "score" => 3,
            "evidence_type" => "desk",
            "evidence_ids" => refs,
            "rationale" => "Mock rating"
          }
        ]
      end

    %{
      "summary" => "Mock score for #{get_in(input, [:segment, :name])}",
      "ratings" => ratings,
      "next_move_suggestion" => "narrow",
      "next_experiment" => "Sean Ellis survey with 40 active users",
      "claims" =>
        if(refs == [], do: [], else: [%{"text" => "Mock claim", "evidence_ids" => refs}])
    }
  end
end
