defmodule Atlas.Agents.CompetitorAnalyst do
  @moduledoc """
  Alternatives, including spreadsheets, agencies and doing nothing.

  Runs in two modes: `"discover"` lists the alternatives once; `"analyze"`
  runs in parallel, one per alternative, and returns observations plus a
  profile for the competitor map.
  """
  use Atlas.Agents.Agent,
    name: "competitor_analyst",
    skills: ~w(guardrails research_method competitive_alternatives),
    allow_web: true

  alias Atlas.Agents.Schemas

  @codes ~w(competitor_present competitor_price positioning_gap feature_gap price_anchor note)
  @kinds ~w(direct indirect diy agency do_nothing)

  defmodule Alternative do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset
    @primary_key false
    embedded_schema do
      field :name, :string
      field :kind, :string
      field :url, :string
      field :segments, {:array, :string}, default: []
    end

    def changeset(a, attrs) do
      a
      |> cast(attrs, [:name, :kind, :url, :segments])
      |> validate_required([:name, :kind])
      |> validate_inclusion(:kind, ~w(direct indirect diy agency do_nothing))
    end
  end

  embedded_schema do
    field :mode, :string
    field :profile, :map
    embeds_many :alternatives, Alternative
    embeds_many :observations, Schemas.ObservationDraft
  end

  def allowed_codes, do: @codes
  def kinds, do: @kinds

  @impl true
  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [:mode, :profile])
    |> cast_embed(:alternatives)
    |> cast_embed(:observations)
  end

  @impl true
  def validate(output, %{mode: "discover"}) do
    n = length(output.alternatives)

    cond do
      n < 2 or n > 10 ->
        {:error, ["list between 2 and 10 alternatives"]}

      not Enum.any?(output.alternatives, &(&1.kind in ["diy", "do_nothing", "agency"])) ->
        {:error, ["include at least one non-software alternative (diy, agency or do_nothing)"]}

      true ->
        :ok
    end
  end

  def validate(output, %{mode: "analyze"}) do
    cond do
      output.observations == [] ->
        {:error, ["return at least one observation"]}

      true ->
        with :ok <- Schemas.check_codes(output.observations, @codes),
             do: Schemas.check_sources(output.observations)
    end
  end

  @impl true
  def role do
    "You map what customers use today instead of this product: direct competitors, indirect tools, " <>
      "spreadsheets and other do-it-yourself fixes, agencies or accountants, and simply doing nothing."
  end

  @impl true
  def build_prompt(%{mode: "discover"} = input) do
    """
    Mode: discover. List the alternatives these segments use today. For each give a kind
    (#{Enum.join(@kinds, ", ")}), a URL when it exists, and the segment names it serves.
    Reply with mode "discover" and an alternatives list.

    #{section("Product brief", input[:brief])}#{section("Segments", input[:segments])}#{feedback(input)}
    """
  end

  def build_prompt(%{mode: "analyze"} = input) do
    """
    Mode: analyze. Profile this one alternative: price, positioning, strengths, weaknesses, and
    the gaps it leaves for these segments. Return observations (allowed codes:
    #{Enum.join(@codes, ", ")}) with sources; set "segment" to a segment name when a gap is
    specific to it. Put strengths, weaknesses, price and positioning in "profile".

    #{section("Product brief", input[:brief])}#{section("Alternative", input[:alternative])}#{section("Segments", input[:segments])}#{feedback(input)}
    """
  end

  @impl true
  def output_example do
    %{
      "mode" => "analyze",
      "alternatives" => [
        %{
          "name" => "Chartered accountant",
          "kind" => "agency",
          "url" => nil,
          "segments" => ["GST-registered freelance designers"]
        }
      ],
      "profile" => %{
        "price" => "₹2,000–5,000 per quarter",
        "positioning" => "Done for you",
        "strengths" => ["Trusted"],
        "weaknesses" => ["Slow turnaround"]
      },
      "observations" => [
        %{
          "segment" => "GST-registered freelance designers",
          "signal_code" => "competitor_price",
          "value_num" => 3000,
          "value_text" => "Typical CA fee per quarter (INR)",
          "confidence" => 0.6,
          "source_url" => "https://example.com/ca-fees"
        }
      ]
    }
  end

  @impl true
  def mock_output(%{mode: "discover"} = input) do
    segs = input |> Map.get(:segments, []) |> Enum.map(&(&1[:name] || &1["name"]))

    %{
      "mode" => "discover",
      "alternatives" => [
        %{"name" => "Spreadsheets", "kind" => "diy", "url" => nil, "segments" => segs},
        %{
          "name" => "Generic SaaS tool",
          "kind" => "direct",
          "url" => "https://example.com",
          "segments" => segs
        },
        %{"name" => "Do nothing", "kind" => "do_nothing", "url" => nil, "segments" => segs}
      ]
    }
  end

  def mock_output(%{mode: "analyze"} = input) do
    alt = get_in(input, [:alternative, :name]) || "alternative"

    %{
      "mode" => "analyze",
      "profile" => %{
        "price" => "unknown",
        "positioning" => "Mock profile of #{alt}",
        "strengths" => ["familiar"],
        "weaknesses" => ["manual"]
      },
      "observations" => [
        Atlas.Agents.Mock.obs("competitor_present", 1, "#{alt} is used today"),
        Atlas.Agents.Mock.obs("positioning_gap", nil, "#{alt} leaves the core job manual")
      ]
    }
  end
end
