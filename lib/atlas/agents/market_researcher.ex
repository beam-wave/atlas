defmodule Atlas.Agents.MarketResearcher do
  @moduledoc "Market size, trends, regulation and reachability for one segment (desk evidence)."
  use Atlas.Agents.Agent,
    name: "market_researcher",
    skills: ~w(guardrails research_method problem_intensity),
    allow_web: true

  alias Atlas.Agents.Schemas

  @codes ~w(market_size market_trend regulation community_size channel_cost_estimate pain_mention_volume current_spend competitor_price note)

  def allowed_codes, do: @codes

  embedded_schema do
    field :summary, :string
    embeds_many :observations, Schemas.ObservationDraft
  end

  @impl true
  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [:summary])
    |> cast_embed(:observations, required: true)
    |> validate_length(:observations, min: 1, max: 15)
  end

  @impl true
  def validate(%{observations: obs}, _input) do
    with :ok <- Schemas.check_codes(obs, @codes), do: Schemas.check_sources(obs)
  end

  @impl true
  def role do
    "You do desk research on one customer segment: how big it is, where it gathers, what it spends, " <>
      "and what rules shape it. Each finding is one observation with a real source URL."
  end

  @impl true
  def build_prompt(input) do
    """
    Research this segment. Return observations only for facts you can attribute to a source you
    actually read; put the URL in source_url. Use confidence to say how much you trust each one.
    Allowed signal codes: #{Enum.join(@codes, ", ")}.

    #{section("Product brief", input[:brief])}#{section("Segment", input[:segment])}#{feedback(input)}
    """
  end

  @impl true
  def output_example do
    %{
      "summary" => "Large, reachable through two communities; GST rules raise the filing burden",
      "observations" => [
        %{
          "signal_code" => "community_size",
          "value_num" => 48_000,
          "value_text" => "Members of r/IndianDesigners",
          "confidence" => 0.7,
          "source_url" => "https://www.reddit.com/r/IndianDesigners/"
        }
      ]
    }
  end

  @impl true
  def mock_output(input) do
    seg = get_in(input, [:segment, :name]) || "segment"

    %{
      "summary" => "Mock desk research for #{seg}",
      "observations" => [
        Atlas.Agents.Mock.obs("community_size", 25_000, "Online community members for #{seg}"),
        Atlas.Agents.Mock.obs("market_trend", nil, "Demand for tools serving #{seg} is growing"),
        Atlas.Agents.Mock.obs("current_spend", 1500, "Monthly spend on workarounds (INR)")
      ]
    }
  end
end

defmodule Atlas.Agents.Mock do
  @moduledoc false
  # Helpers for agents' canned outputs. Mock evidence is labelled as such.

  def obs(code, num, text, extra \\ %{}) do
    Map.merge(
      %{
        "signal_code" => code,
        "value_num" => num,
        "value_text" => text,
        "confidence" => 0.5,
        "source_note" => "MOCK DATA from the mock adapter, not real evidence"
      },
      extra
    )
  end

  @doc "Evidence refs from a digest, for citing in mock claims."
  def refs(evidence, n \\ 2) do
    evidence |> List.wrap() |> Enum.map(& &1["ref"]) |> Enum.reject(&is_nil/1) |> Enum.take(n)
  end
end
