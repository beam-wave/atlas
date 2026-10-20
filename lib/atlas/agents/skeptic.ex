defmodule Atlas.Agents.Skeptic do
  @moduledoc "Reviews every producer output: unsupported claims, bias, leading questions, segment overlap."
  use Atlas.Agents.Agent,
    name: "skeptic",
    skills: ~w(guardrails critical_review survey_design research_method)

  @issue_kinds ~w(unsupported_claim bias leading_question segment_overlap vanity_metric fabrication unclear other)

  defmodule Issue do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset
    @primary_key false
    embedded_schema do
      field :kind, :string
      field :detail, :string
      field :fix, :string
    end

    def changeset(i, attrs) do
      i
      |> cast(attrs, [:kind, :detail, :fix])
      |> validate_required([:kind, :detail])
      |> update_change(
        :kind,
        &if(
          &1 in ~w(unsupported_claim bias leading_question segment_overlap vanity_metric fabrication unclear other),
          do: &1,
          else: "other"
        )
      )
    end
  end

  embedded_schema do
    field :verdict, :string
    embeds_many :issues, Issue
  end

  def issue_kinds, do: @issue_kinds

  @impl true
  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [:verdict])
    |> update_change(:verdict, &(&1 && String.upcase(&1)))
    |> validate_required([:verdict])
    |> validate_inclusion(:verdict, ~w(PASS REVISE))
    |> cast_embed(:issues)
  end

  @impl true
  def validate(%{verdict: "REVISE", issues: []}, _),
    do: {:error, ["REVISE needs at least one issue with a fix"]}

  def validate(_, _), do: :ok

  @impl true
  def role do
    "You are the reviewer. You look for claims the evidence does not support, confirmation bias, " <>
      "leading or hypothetical questions, overlapping segments and vanity metrics. You return PASS, " <>
      "or REVISE with concrete fixes. You do not rewrite the work yourself."
  end

  @impl true
  def build_prompt(input) do
    """
    Review this #{input[:kind]} output. PASS if it is sound enough for a person to act on. REVISE
    only for problems that would mislead a founder; list each with a concrete fix. Issue kinds:
    #{Enum.join(@issue_kinds, ", ")}.

    #{section("Output under review", input[:output])}#{section("Evidence available", input[:evidence])}#{section("Context", input[:context])}
    """
  end

  @impl true
  def output_example do
    %{
      "verdict" => "REVISE",
      "issues" => [
        %{
          "kind" => "segment_overlap",
          "detail" => "Freelance designers and creative freelancers overlap",
          "fix" => "Merge them or split by GST registration"
        }
      ]
    }
  end

  @impl true
  def mock_output(_input), do: %{"verdict" => "PASS", "issues" => []}
end
