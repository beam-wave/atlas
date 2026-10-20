defmodule Atlas.Agents.AgentsTest do
  @moduledoc """
  Contract tests: every agent's example output and mock output must pass its
  own schema and validation, and prompts must carry their inputs.
  """
  use ExUnit.Case, async: true

  alias Atlas.Agents.{
    Analyst,
    CompetitorAnalyst,
    EvidenceSynthesizer,
    ExperimentDesigner,
    Intake,
    MarketResearcher,
    PMFScorer,
    PositioningWriter,
    SegmentStrategist,
    Skeptic,
    VoCMiner
  }

  @segment %{
    id: 1,
    name: "Freelance designers",
    criteria: %{},
    job_to_be_done: %{"functional" => "File GST"}
  }
  @evidence [
    %{"ref" => "E1", "signal_code" => "pain_quote"},
    %{"ref" => "E2", "signal_code" => "community_size"}
  ]

  @inputs %{
    Intake => %{product: %{name: "LedgerLite", description: "AI bookkeeping"}},
    SegmentStrategist => %{brief: %{"product_name" => "LedgerLite"}},
    MarketResearcher => %{brief: %{}, segment: @segment},
    VoCMiner => %{brief: %{}, segment: @segment},
    PositioningWriter => %{brief: %{}, segment: @segment, evidence: @evidence},
    ExperimentDesigner => %{
      brief: %{},
      segment: @segment,
      hypothesis: %{statement: "s", falsified_if: "f"}
    },
    EvidenceSynthesizer => %{brief: %{}, material_kind: "transcript", material: "text"},
    Skeptic => %{kind: "brief", output: %{}},
    PMFScorer => %{brief: %{}, segment: @segment, evidence: @evidence},
    Analyst => %{
      rejections: [%{"note" => "too vague"}, %{"note" => "too vague again"}],
      skills: [%{"name" => "clear_writing"}]
    }
  }

  defp validate(agent, raw, input) do
    with {:ok, out} <-
           agent.changeset(struct(agent), raw) |> Ecto.Changeset.apply_action(:validate) do
      agent.validate(out, input)
    end
  end

  for {agent, input} <- @inputs do
    @agent agent
    @input input

    test "#{inspect(agent)} mock output satisfies its own contract" do
      raw = @agent.mock_output(@input) |> Jason.encode!() |> Jason.decode!()
      assert :ok = validate(@agent, raw, @input)
    end

    test "#{inspect(agent)} has a role, skills and a prompt" do
      assert is_binary(@agent.role())
      assert @agent.default_skills() != []
      assert is_binary(@agent.build_prompt(@input))
      assert is_map(@agent.output_example())
    end
  end

  test "competitor analyst works in both modes" do
    discover = %{mode: "discover", brief: %{}, segments: [@segment]}

    analyze = %{
      mode: "analyze",
      brief: %{},
      alternative: %{name: "Spreadsheets"},
      segments: [@segment]
    }

    for input <- [discover, analyze] do
      raw = CompetitorAnalyst.mock_output(input) |> Jason.encode!() |> Jason.decode!()
      assert :ok = validate(CompetitorAnalyst, raw, input)
      assert CompetitorAnalyst.build_prompt(input) =~ "Mode: #{input.mode}"
    end

    only_software = %{
      "mode" => "discover",
      "alternatives" => [
        %{"name" => "A", "kind" => "direct"},
        %{"name" => "B", "kind" => "indirect"}
      ]
    }

    assert {:error, [msg]} = validate(CompetitorAnalyst, only_software, discover)
    assert msg =~ "non-software"
  end

  # The segment strategist's example shows one segment for brevity; its prompt asks for 4–8.
  test "example outputs validate (they are shown to the model as the contract)" do
    for agent <- [
          Intake,
          MarketResearcher,
          VoCMiner,
          PositioningWriter,
          ExperimentDesigner,
          Skeptic,
          PMFScorer,
          Analyst
        ] do
      raw = agent.output_example() |> Jason.encode!() |> Jason.decode!()
      result = agent.changeset(struct(agent), raw) |> Ecto.Changeset.apply_action(:validate)
      assert {:ok, _} = result, "#{inspect(agent)} example does not cast: #{inspect(result)}"
    end
  end

  describe "validation rules" do
    test "segment strategist needs 4–8 distinct segments" do
      raw = SegmentStrategist.mock_output(%{}) |> Jason.encode!() |> Jason.decode!()
      three = %{"segments" => Enum.take(raw["segments"], 3)}
      assert {:error, %Ecto.Changeset{}} = validate(SegmentStrategist, three, %{})

      dupes = %{"segments" => List.duplicate(hd(raw["segments"]), 4)}

      assert {:error, ["segment names must be distinct"]} =
               validate(SegmentStrategist, dupes, %{})
    end

    test "researchers may only emit their own signal codes, with sources" do
      bad = %{
        "observations" => [
          %{
            "signal_code" => "sean_ellis_very_disappointed_pct",
            "value_num" => 90,
            "confidence" => 1,
            "source_url" => "x"
          }
        ]
      }

      assert {:error, [msg]} = validate(MarketResearcher, bad, %{})
      assert msg =~ "not allowed"

      unsourced = %{
        "observations" => [
          %{"signal_code" => "market_size", "value_num" => 1, "confidence" => 0.5}
        ]
      }

      assert {:error, [msg]} = validate(MarketResearcher, unsourced, %{})
      assert msg =~ "source"

      unknown = %{
        "observations" => [
          %{"signal_code" => "vibes", "value_num" => 1, "confidence" => 0.5, "source_url" => "x"}
        ]
      }

      assert {:error, %Ecto.Changeset{}} = validate(MarketResearcher, unknown, %{})
    end

    test "VoC quotes need a URL" do
      raw = %{
        "observations" => [
          %{
            "signal_code" => "pain_quote",
            "value_text" => "ugh",
            "confidence" => 0.9,
            "source_note" => "forum"
          }
        ]
      }

      assert {:error, ["every pain_quote needs the source_url it was copied from"]} =
               validate(VoCMiner, raw, %{})
    end

    test "experiment designer only accepts computable metrics, honest smoke tests and clean surveys" do
      base = ExperimentDesigner.mock_output(%{}) |> Jason.encode!() |> Jason.decode!()

      bad_metric =
        put_in(base, ["thresholds", "criteria"], [
          %{"metric" => "happiness", "operator" => ">=", "value" => 1}
        ])

      assert {:error, [msg]} = validate(ExperimentDesigner, bad_metric, %{})
      assert msg =~ "happiness"

      smoke = %{
        base
        | "kind" => "smoke_test",
          "design" => %{"headline" => "x"},
          "thresholds" => %{
            "criteria" => [
              %{"metric" => "signup_conversion_pct", "operator" => ">=", "value" => 5}
            ],
            "min_sample" => 200
          }
      }

      assert {:error, [msg]} = validate(ExperimentDesigner, smoke, %{})
      assert msg =~ "disclosure"

      leading =
        put_in(base, ["design", "questions"], [%{"text" => "Would you buy it?", "type" => "open"}])

      assert {:error, [msg]} = validate(ExperimentDesigner, leading, %{})
      assert msg =~ "hypothetical"
    end

    test "scorer may not rate code-computed dimensions or leave ratings uncited" do
      base = %{"summary" => "s", "next_experiment" => "e", "next_move_suggestion" => "narrow"}

      se =
        Map.put(base, "ratings", [
          %{
            "dimension" => "sean_ellis",
            "score" => 5,
            "evidence_ids" => ["E1"],
            "rationale" => "r"
          }
        ])

      assert {:error, [msg]} = validate(PMFScorer, se, %{})
      assert msg =~ "computed by code"

      uncited =
        Map.put(base, "ratings", [
          %{"dimension" => "reachability", "score" => 3, "evidence_ids" => [], "rationale" => "r"}
        ])

      assert {:error, [msg]} = validate(PMFScorer, uncited, %{})
      assert msg =~ "cites"

      assert {:error, %Ecto.Changeset{}} =
               validate(PMFScorer, Map.put(base, "next_move_suggestion", "yolo"), %{})
    end

    test "synthesizer must flag interviews for transcripts" do
      raw = %{"summary" => "s", "observations" => []}
      assert {:error, [msg]} = validate(EvidenceSynthesizer, raw, %{material_kind: "transcript"})
      assert msg =~ "pain_confirmed"
      assert :ok = validate(EvidenceSynthesizer, raw, %{material_kind: "survey open text"})
    end

    test "analyst may only target known skills" do
      raw = %{"proposals" => [%{"skill" => "ghost", "rationale" => "r", "addition" => "a"}]}

      assert {:error, ["unknown skills: ghost"]} =
               validate(Analyst, raw, %{skills: [%{"name" => "clear_writing"}]})
    end
  end

  test "prompts include revision feedback when present" do
    prompt = Intake.build_prompt(Map.put(@inputs[Intake], :revision_feedback, ["say less"]))
    assert prompt =~ "Fix these issues from review"
    assert prompt =~ "- say less"
  end
end
