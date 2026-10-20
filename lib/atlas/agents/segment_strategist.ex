defmodule Atlas.Agents.SegmentStrategist do
  @moduledoc "Proposes 4–8 customer segments, each with a job to be done and a falsifiable hypothesis."
  use Atlas.Agents.Agent,
    name: "segment_strategist",
    skills: ~w(guardrails research_method icp_definition jobs_to_be_done problem_intensity)

  defmodule Hypothesis do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset
    @primary_key false
    embedded_schema do
      field :statement, :string
      field :falsified_if, :string
    end

    def changeset(h, attrs),
      do:
        h
        |> cast(attrs, [:statement, :falsified_if])
        |> validate_required([:statement, :falsified_if])
  end

  defmodule Segment do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset
    @primary_key false
    embedded_schema do
      field :name, :string
      field :criteria, :map, default: %{}
      field :job_to_be_done, :map, default: %{}
      field :rationale, :string
      embeds_one :hypothesis, Hypothesis
    end

    def changeset(s, attrs) do
      s
      |> cast(attrs, [:name, :criteria, :job_to_be_done, :rationale])
      |> validate_required([:name, :rationale])
      |> cast_embed(:hypothesis, required: true)
      |> validate_change(:job_to_be_done, fn _, jtbd ->
        if is_binary(jtbd["functional"]) and jtbd["functional"] != "",
          do: [],
          else: [job_to_be_done: "needs a functional job"]
      end)
    end
  end

  embedded_schema do
    embeds_many :segments, Segment
  end

  @impl true
  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [])
    |> cast_embed(:segments, required: true)
    |> validate_length(:segments, min: 4, max: 8)
  end

  @impl true
  def validate(%{segments: segments}, _input) do
    names = Enum.map(segments, &String.downcase(String.trim(&1.name)))

    if length(Enum.uniq(names)) == length(names),
      do: :ok,
      else: {:error, ["segment names must be distinct"]}
  end

  @impl true
  def role do
    "You propose distinct, non-overlapping customer segments narrow enough to reach and test. " <>
      "Each segment gets a job to be done and one hypothesis that a cheap experiment could falsify."
  end

  @impl true
  def build_prompt(input) do
    """
    Propose 4 to 8 customer segments for this product. Make them mutually exclusive: a person
    should fit one segment, not several. Prefer narrow segments you can name a channel for.

    #{section("Product brief", input[:brief])}#{section("Previous segments and how they scored", input[:previous])}#{section("Direction from the last verdict", input[:direction])}#{feedback(input)}
    """
  end

  @impl true
  def output_example do
    %{
      "segments" => [
        %{
          "name" => "GST-registered freelance designers",
          "criteria" => %{
            "firmographic" => ["solo freelancer", "GST-registered", "₹20L+ annual billing"],
            "psychographic" => ["does own books", "dreads quarterly filing"],
            "disqualifiers" => ["already pays a CA monthly retainer"]
          },
          "job_to_be_done" => %{
            "functional" => "File accurate GST returns without a CA",
            "emotional" => "Stop worrying about notices",
            "social" => "Look professional to agency clients"
          },
          "rationale" => "Highest filing burden among freelancers; active in design communities",
          "hypothesis" => %{
            "statement" => "Designers spend 4+ hours per quarter reconciling invoices for GST",
            "falsified_if" =>
              "Fewer than 30% of interviewed designers report 2+ hours per quarter"
          }
        }
      ]
    }
  end

  @impl true
  def mock_output(input) do
    product = get_in(input, [:brief, "product_name"]) || "the product"
    offset = length(input[:previous] || [])

    segments =
      for {name, job} <- mock_segments() |> Stream.cycle() |> Stream.drop(offset) |> Enum.take(4) do
        %{
          "name" => name,
          "criteria" => %{
            "firmographic" => [name],
            "psychographic" => ["actively looking for a better way"],
            "disqualifiers" => []
          },
          "job_to_be_done" => %{
            "functional" => job,
            "emotional" => "feel in control",
            "social" => "look competent"
          },
          "rationale" => "Mock segment for #{product}",
          "hypothesis" => %{
            "statement" => "#{name} spend 2+ hours a week on: #{job}",
            "falsified_if" => "Fewer than 30% of #{name} interviewed report 2+ hours a week"
          }
        }
      end

    %{"segments" => segments}
  end

  defp mock_segments do
    [
      {"Solo freelancers", "Keep client work organised"},
      {"Small agencies", "Coordinate a small team's work"},
      {"Consultants", "Bill clients accurately"},
      {"Tutors", "Schedule and collect fees"},
      {"Indie developers", "Ship side projects faster"},
      {"Content creators", "Track sponsorship income"}
    ]
  end
end
