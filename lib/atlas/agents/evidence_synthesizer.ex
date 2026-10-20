defmodule Atlas.Agents.EvidenceSynthesizer do
  @moduledoc """
  Turns uploaded interview transcripts and open-text survey answers into
  experimental observations. Numbers (Sean Ellis %, conversion, retention)
  are computed by code, not by this agent.
  """
  use Atlas.Agents.Agent,
    name: "evidence_synthesizer",
    skills: ~w(guardrails research_method jobs_to_be_done problem_intensity retention_signals)

  alias Atlas.Agents.Schemas

  @codes ~w(pain_quote pain_frequency pain_severity current_spend workaround_seeking switching_intent competitor_present positioning_gap price_anchor note)

  def allowed_codes, do: @codes

  embedded_schema do
    field :summary, :string
    field :interview, :map
    embeds_many :observations, Schemas.ObservationDraft
  end

  @impl true
  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [:summary, :interview])
    |> validate_required([:summary])
    |> cast_embed(:observations)
  end

  @impl true
  def validate(out, input) do
    with :ok <- Schemas.check_codes(out.observations, @codes) do
      if input[:material_kind] == "transcript" and not interview_flags?(out.interview) do
        {:error,
         [
           "for a transcript, set interview.pain_confirmed, interview.past_spend and interview.switching_intent to true or false"
         ]}
      else
        :ok
      end
    end
  end

  defp interview_flags?(%{} = i),
    do: Enum.all?(~w(pain_confirmed past_spend switching_intent), &is_boolean(i[&1]))

  defp interview_flags?(_), do: false

  @impl true
  def role do
    "You read real customer material — interview transcripts, open-text survey answers — and record " <>
      "what it shows. You quote exactly, judge past behaviour over stated intent, and never add what is not there."
  end

  @impl true
  def build_prompt(input) do
    """
    Material kind: #{input[:material_kind]}. Record observations from it (allowed codes:
    #{Enum.join(@codes, ", ")}); set "segment" to the matching segment name when clear.
    Quotes go verbatim in value_text with source_note naming the material.
    #{if input[:material_kind] == "transcript", do: ~s(Also return "interview": {"pain_confirmed": bool, "past_spend": bool, "switching_intent": bool, "segment": name or null} — true only when the interviewee describes it happening in the past, not "would".), else: ""}

    #{section("Product brief", input[:brief])}#{section("Segments", input[:segments])}#{section("Experiment", input[:experiment])}#{section("Material", input[:material])}#{feedback(input)}
    """
  end

  @impl true
  def output_example do
    %{
      "summary" => "Interviewee files GST alone and lost a weekend last quarter",
      "interview" => %{
        "pain_confirmed" => true,
        "past_spend" => false,
        "switching_intent" => true,
        "segment" => "GST-registered freelance designers"
      },
      "observations" => [
        %{
          "segment" => "GST-registered freelance designers",
          "signal_code" => "pain_quote",
          "value_text" => "Last quarter I spent my whole Sunday on it",
          "confidence" => 0.9,
          "source_note" => "Interview 3 transcript"
        }
      ]
    }
  end

  @impl true
  def mock_output(input) do
    base = %{
      "summary" => "Mock synthesis of #{input[:material_kind]}",
      "observations" => [
        Atlas.Agents.Mock.obs("pain_quote", nil, "It took me most of a day last time", %{
          "confidence" => 0.7
        })
      ]
    }

    if input[:material_kind] == "transcript",
      do:
        Map.put(base, "interview", %{
          "pain_confirmed" => true,
          "past_spend" => false,
          "switching_intent" => true,
          "segment" => nil
        }),
      else: base
  end
end
