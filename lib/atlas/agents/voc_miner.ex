defmodule Atlas.Agents.VoCMiner do
  @moduledoc "Pain language, intensity and workarounds from public reviews, forums and support threads."
  use Atlas.Agents.Agent,
    name: "voc_miner",
    skills: ~w(guardrails research_method voice_of_customer_mining problem_intensity),
    allow_web: true

  alias Atlas.Agents.Schemas

  @codes ~w(pain_quote pain_frequency pain_severity workaround_seeking pain_mention_volume current_spend switching_intent note)

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
    |> validate_length(:observations, min: 1, max: 20)
  end

  @impl true
  def validate(%{observations: obs}, _input) do
    with :ok <- Schemas.check_codes(obs, @codes), :ok <- Schemas.check_sources(obs) do
      quotes_without_url =
        Enum.count(obs, &(&1.signal_code == "pain_quote" and &1.source_url in [nil, ""]))

      if quotes_without_url == 0,
        do: :ok,
        else: {:error, ["every pain_quote needs the source_url it was copied from"]}
    end
  end

  @impl true
  def role do
    "You mine public customer language — reviews, forums, support threads — for real pain. " <>
      "Quotes are verbatim, attributed to their URL, stripped of names and contact details."
  end

  @impl true
  def build_prompt(input) do
    """
    Find how people in this segment describe the problem in their own words. Separate real pain
    (frequency, cost, workarounds) from casual complaints. Put verbatim quotes in value_text of a
    pain_quote observation with its source_url. Allowed signal codes: #{Enum.join(@codes, ", ")}.

    #{section("Product brief", input[:brief])}#{section("Segment", input[:segment])}#{feedback(input)}
    """
  end

  @impl true
  def output_example do
    %{
      "summary" => "Strong, frequent pain around quarterly GST reconciliation",
      "observations" => [
        %{
          "signal_code" => "pain_quote",
          "value_text" => "Every quarter I lose a weekend matching invoices to bank entries",
          "confidence" => 0.8,
          "source_url" => "https://www.reddit.com/r/IndiaTax/comments/example"
        },
        %{
          "signal_code" => "pain_frequency",
          "value_num" => 4,
          "value_text" => "Quarterly, recurring",
          "confidence" => 0.6,
          "source_note" => "Pattern across 12 threads"
        }
      ]
    }
  end

  @impl true
  def mock_output(input) do
    seg = get_in(input, [:segment, :name]) || "segment"

    %{
      "summary" => "Mock voice-of-customer for #{seg}",
      "observations" => [
        Atlas.Agents.Mock.obs("pain_quote", nil, "This takes me hours every week (#{seg})", %{
          "source_url" => "https://example.com/mock-thread"
        }),
        Atlas.Agents.Mock.obs("pain_frequency", 3, "Weekly"),
        Atlas.Agents.Mock.obs("workaround_seeking", 1, "Spreadsheets and manual checklists")
      ]
    }
  end
end
