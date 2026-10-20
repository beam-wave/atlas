defmodule Atlas.Agents.PositioningWriter do
  @moduledoc "Positioning for a top segment (Dunford sequence) plus landing-page copy variants."
  use Atlas.Agents.Agent,
    name: "positioning_writer",
    skills: ~w(guardrails clear_writing positioning competitive_alternatives)

  alias Atlas.Agents.Schemas.Claim

  embedded_schema do
    field :alternatives, {:array, :string}, default: []
    field :unique_attributes, {:array, :string}, default: []
    field :value, {:array, :string}, default: []
    field :best_fit_customer, :string
    field :market_category, :string
    field :headline_variants, {:array, :string}, default: []
    field :landing_copy, :map
    embeds_many :claims, Claim
  end

  @impl true
  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [
      :alternatives,
      :unique_attributes,
      :value,
      :best_fit_customer,
      :market_category,
      :headline_variants,
      :landing_copy
    ])
    |> validate_required([:best_fit_customer, :market_category, :landing_copy])
    |> Atlas.Agents.Agent.validate_count(:alternatives, 1, 10)
    |> Atlas.Agents.Agent.validate_count(:unique_attributes, 1, 10)
    |> Atlas.Agents.Agent.validate_count(:headline_variants, 2, 5)
    |> cast_embed(:claims, required: true)
    |> validate_length(:claims, min: 1)
  end

  @impl true
  def role do
    "You write positioning for one segment using April Dunford's sequence, then landing-page copy. " <>
      "Every factual claim cites the evidence that supports it. Plain words; no hype."
  end

  @impl true
  def build_prompt(input) do
    """
    Write positioning for this segment: alternatives → unique attributes → value → best-fit
    customer → market category. Then two to five headline variants and landing copy
    (headline, subhead, 3 bullets, call to action). List each factual claim in "claims" with the
    evidence IDs behind it.

    #{section("Product brief", input[:brief])}#{section("Segment", input[:segment])}#{section("Scorecard for this segment", input[:scorecard])}#{section("Evidence", input[:evidence])}#{feedback(input)}
    """
  end

  @impl true
  def output_example do
    %{
      "alternatives" => ["Chartered accountant", "Spreadsheets"],
      "unique_attributes" => ["Reads bank statements directly"],
      "value" => ["GST filing in 20 minutes instead of a weekend"],
      "best_fit_customer" =>
        "GST-registered freelance designers billing ₹20L+ who do their own books",
      "market_category" => "GST filing for freelancers",
      "headline_variants" => ["File GST in 20 minutes", "Your quarterly GST, done before lunch"],
      "landing_copy" => %{
        "headline" => "File GST in 20 minutes",
        "subhead" => "...",
        "bullets" => ["..."],
        "cta" => "Join the waitlist"
      },
      "claims" => [
        %{
          "text" => "Designers lose a weekend each quarter to reconciliation",
          "evidence_ids" => ["E12", "E15"]
        }
      ]
    }
  end

  @impl true
  def mock_output(input) do
    seg = get_in(input, [:segment, :name]) || "segment"
    refs = Atlas.Agents.Mock.refs(input[:evidence])

    %{
      "alternatives" => ["Spreadsheets", "Do nothing"],
      "unique_attributes" => ["Built for #{seg}"],
      "value" => ["Saves hours each week"],
      "best_fit_customer" => seg,
      "market_category" => "tools for #{seg}",
      "headline_variants" => ["Built for #{seg}", "Get your hours back"],
      "landing_copy" => %{
        "headline" => "Built for #{seg}",
        "subhead" => "Mock copy",
        "bullets" => ["One", "Two", "Three"],
        "cta" => "Join the waitlist"
      },
      "claims" => [%{"text" => "#{seg} spend hours on this today", "evidence_ids" => refs}]
    }
  end
end
