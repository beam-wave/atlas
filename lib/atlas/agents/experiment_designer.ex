defmodule Atlas.Agents.ExperimentDesigner do
  @moduledoc """
  The cheapest test for one hypothesis, with thresholds fixed up front.

  Threshold metrics must be ones Atlas computes from uploads, so the
  verdict is arithmetic rather than opinion.
  """
  use Atlas.Agents.Agent,
    name: "experiment_designer",
    skills:
      ~w(guardrails clear_writing experiment_thresholds survey_design interview_guide smoke_test_design)

  @metrics %{
    "survey" =>
      ~w(responses sean_ellis_very_disappointed_pct sean_ellis_somewhat_disappointed_pct sean_ellis_responses vw_too_cheap vw_bargain vw_expensive vw_too_expensive),
    "interview" =>
      ~w(interview_count interview_pain_confirmed_pct interview_past_spend_pct interview_switching_intent_pct),
    "smoke_test" => ~w(visits signups preorders signup_conversion_pct cost_per_signup)
  }

  def metrics, do: @metrics

  embedded_schema do
    field :kind, :string
    field :title, :string
    field :rationale, :string
    field :design, :map
    field :thresholds, :map
    field :cost_estimate, :string
  end

  @impl true
  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [:kind, :title, :rationale, :design, :thresholds, :cost_estimate])
    |> validate_required([:kind, :title, :rationale, :design, :thresholds])
    |> validate_inclusion(:kind, Map.keys(@metrics))
  end

  @impl true
  def validate(out, _input) do
    criteria = (out.thresholds || %{})["criteria"] || []
    allowed = @metrics[out.kind] || []

    errors =
      [
        if(criteria == [], do: "thresholds.criteria needs at least one criterion"),
        if(not is_number((out.thresholds || %{})["min_sample"]),
          do: "thresholds.min_sample must be a number"
        ),
        for(
          %{"metric" => m} <- criteria,
          m not in allowed,
          do:
            "metric #{m} is not computed for #{out.kind}; use one of #{Enum.join(allowed, ", ")}"
        ),
        for(
          c <- criteria,
          not (is_map(c) and c["operator"] in Atlas.Experiments.Experiment.operators() and
                 is_number(c["value"])),
          do:
            "criterion #{inspect(c)} needs metric, operator (>=, >, <=, <, ==) and numeric value"
        ),
        design_errors(out.kind, out.design || %{})
      ]
      |> List.flatten()
      |> Enum.reject(&is_nil/1)

    lint =
      case out.kind do
        "survey" ->
          case Atlas.Gates.SurveyLint.check(out.design) do
            :ok ->
              []

            {:error, {:survey_lint, issues}} ->
              Enum.map(issues, &"question #{&1["question"]}: #{&1["issue"]}")
          end

        _ ->
          []
      end

    case errors ++ lint do
      [] -> :ok
      all -> {:error, all}
    end
  end

  defp design_errors("survey", d),
    do:
      if(is_list(d["questions"]) and d["questions"] != [],
        do: nil,
        else: "survey design needs questions"
      )

  defp design_errors("interview", d),
    do:
      if(is_list(d["questions"]) and d["questions"] != [],
        do: nil,
        else: "interview design needs questions"
      )

  defp design_errors("smoke_test", d) do
    if is_binary(d["disclosure"]) and String.trim(d["disclosure"]) != "",
      do: nil,
      else:
        "smoke test design needs an honest disclosure telling visitors the product is not live"
  end

  defp design_errors(_, _), do: nil

  @impl true
  def role do
    "You design the cheapest experiment that could falsify one hypothesis, and you fix its success " <>
      "thresholds before any data exists. Questions ask about past behaviour, never hypotheticals."
  end

  @impl true
  def build_prompt(input) do
    """
    Design one experiment for this hypothesis. Pick the cheapest kind that can falsify it:
    "survey", "interview" or "smoke_test". Threshold metrics must come from this list for the
    kind you choose (Atlas computes them from uploads):

    #{Enum.map_join(@metrics, "\n", fn {k, ms} -> "- #{k}: #{Enum.join(ms, ", ")}" end)}

    Design shapes:
    - survey: {"questions": [{"text", "type" (open|single_choice|multi_choice|rating|sean_ellis|van_westendorp), "options"}]}
    - interview: {"intro", "questions": [...], "do_not": [...], "count": n}
    - smoke_test: {"headline", "subhead", "cta", "disclosure", "channel", "budget"}

    #{section("Product brief", input[:brief])}#{section("Segment", input[:segment])}#{section("Hypothesis", input[:hypothesis])}#{section("Evidence so far", input[:evidence])}#{section("Experiments already run", input[:previous])}#{feedback(input)}
    """
  end

  @impl true
  def output_example do
    %{
      "kind" => "survey",
      "title" => "Sean Ellis + filing-time survey for freelance designers",
      "rationale" => "Cheapest way to size the pain across 100+ designers",
      "design" => %{
        "questions" => [
          %{
            "text" => "How did you file your last GST return?",
            "type" => "single_choice",
            "options" => ["Myself", "A CA", "Not registered"]
          },
          %{
            "text" => "How would you feel if you could no longer use LedgerLite?",
            "type" => "sean_ellis",
            "options" => ["Very disappointed", "Somewhat disappointed", "Not disappointed"]
          }
        ]
      },
      "thresholds" => %{
        "criteria" => [
          %{"metric" => "sean_ellis_very_disappointed_pct", "operator" => ">=", "value" => 40}
        ],
        "min_sample" => 40
      },
      "cost_estimate" => "₹0, 2 weeks via design communities"
    }
  end

  @impl true
  def mock_output(input) do
    seg = get_in(input, [:segment, :name]) || "users"

    %{
      "kind" => "survey",
      "title" => "Pain and Sean Ellis survey for #{seg}",
      "rationale" => "Mock design: cheapest test of the hypothesis",
      "design" => %{
        "questions" => [
          %{"text" => "When did you last deal with this problem?", "type" => "open"},
          %{"text" => "What did you use to handle it last time?", "type" => "open"},
          %{
            "text" => "How would you feel if you could no longer use the product?",
            "type" => "sean_ellis",
            "options" => ["Very disappointed", "Somewhat disappointed", "Not disappointed"]
          }
        ]
      },
      "thresholds" => %{
        "criteria" => [
          %{"metric" => "sean_ellis_very_disappointed_pct", "operator" => ">=", "value" => 40}
        ],
        "min_sample" => 30
      },
      "cost_estimate" => "Free; two weeks"
    }
  end
end
