defmodule Atlas.Agents.Intake do
  @moduledoc "Structures the product brief: what, for whom, claimed pain, price."
  use Atlas.Agents.Agent,
    name: "intake",
    skills: ~w(guardrails clear_writing icp_definition)

  embedded_schema do
    field :product_name, :string
    field :what, :string
    field :for_whom, :string
    field :claimed_pain, :string
    field :price, :string
    field :category, :string
    field :assumptions, {:array, :string}, default: []
    field :open_questions, {:array, :string}, default: []
  end

  @impl true
  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [
      :product_name,
      :what,
      :for_whom,
      :claimed_pain,
      :price,
      :category,
      :assumptions,
      :open_questions
    ])
    |> validate_required([:product_name, :what, :for_whom, :claimed_pain])
    |> Atlas.Agents.Agent.validate_count(:assumptions, 1, 12)
  end

  @impl true
  def role do
    "You turn a founder's product description into a structured brief. Separate what the founder " <>
      "states from what they assume. Do not add facts that are not in the input."
  end

  @impl true
  def build_prompt(%{product: product} = input) do
    """
    Structure this product into a brief. List every untested assumption the description makes
    (who has the pain, how badly, what they pay today) so later agents can test them.

    #{section("Product", product)}#{feedback(input)}
    """
  end

  @impl true
  def output_example do
    %{
      "product_name" => "LedgerLite",
      "what" => "AI bookkeeping that categorises bank transactions and prepares GST returns",
      "for_whom" => "Indian freelancers",
      "claimed_pain" => "Freelancers lose hours each month reconciling invoices for GST filing",
      "price" => "₹499/month",
      "category" => "bookkeeping software",
      "assumptions" => ["Freelancers file GST themselves rather than via a CA"],
      "open_questions" => ["What share of freelancers are GST-registered?"]
    }
  end

  @impl true
  def mock_output(%{product: p}) do
    name = p[:name] || p["name"] || "Product"
    desc = p[:description] || p["description"] || ""

    %{
      "product_name" => name,
      "what" => String.slice(desc, 0, 200),
      "for_whom" => "early adopters described in the product description",
      "claimed_pain" => "the problem the description says #{name} solves",
      "price" => p[:price] || p["price"] || "unknown",
      "category" => "software",
      "assumptions" => [
        "The target users feel this pain often enough to look for a fix",
        "They currently spend time or money on a workaround",
        "They would switch from their current workaround"
      ],
      "open_questions" => ["Which sub-group feels the pain most?"]
    }
  end
end
