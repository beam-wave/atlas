defmodule Atlas.Agents.RunnerTest do
  use Atlas.DataCase, async: false

  import Atlas.Fixtures

  alias Atlas.Agents.{Intake, JSON, PositioningWriter, Runner, Skeptic}
  alias Atlas.LLMStub

  @input %{product: %{name: "LedgerLite", description: "AI bookkeeping for freelancers."}}
  @brief %{
    "product_name" => "LedgerLite",
    "what" => "bookkeeping",
    "for_whom" => "freelancers",
    "claimed_pain" => "GST is slow",
    "assumptions" => ["they file alone"]
  }

  describe "JSON.extract/1" do
    test "handles bare, fenced and chatty replies" do
      assert {:ok, %{"a" => 1}} = JSON.extract(~s({"a":1}))
      assert {:ok, %{"a" => 1}} = JSON.extract("Here you go:\n```json\n{\"a\": 1}\n```\nThanks")

      assert {:ok, %{"a" => %{"b" => 2}}} =
               JSON.extract(~s(Sure! {"a": {"b": 2}} Hope that helps.))

      assert {:error, {:invalid, _}} = JSON.extract("no json here")
      assert {:error, {:invalid, _}} = JSON.extract("[1,2,3]")
      assert {:error, {:invalid, _}} = JSON.extract(nil)
    end
  end

  describe "run/3" do
    test "builds a prompt from skills, task and output contract" do
      test_pid = self()

      LLMStub.stub(fn req ->
        send(test_pid, {:req, req})
        Jason.encode!(@brief)
      end)

      assert {:ok, %Intake{product_name: "LedgerLite"}, meta} = Runner.run(Intake, @input, %{})
      assert meta.attempts == 1
      assert Map.has_key?(meta.skill_versions, "guardrails")

      assert_received {:req, req}
      assert req.agent == "intake"
      assert req.system =~ "Skill: "
      assert req.system =~ "Reply with a single JSON object"
      assert req.prompt =~ "LedgerLite"
      assert req.prompt =~ "## Output format"
    end

    test "retries once with the validation errors, then succeeds" do
      {:ok, calls} = Agent.start_link(fn -> [] end)

      LLMStub.stub(fn req ->
        Agent.update(calls, &[req.prompt | &1])

        if length(Agent.get(calls, & &1)) == 1,
          do: ~s({"product_name": "x"}),
          else: Jason.encode!(@brief)
      end)

      assert {:ok, _, %{attempts: 2}} = Runner.run(Intake, @input, %{})
      [second, _first] = Agent.get(calls, & &1)
      assert second =~ "Your previous reply was rejected"
      assert second =~ "what can't be blank"
    end

    test "fails visibly after two invalid replies and logs it" do
      study = study_fixture()
      LLMStub.stub(fn _ -> "I cannot help with that." end)

      assert {:error, {:invalid_output, "intake", ["reply did not contain a JSON object"]}} =
               Runner.run(Intake, @input, %{study_id: study.id})

      assert [%{payload: %{"agent" => "intake"}}] =
               Atlas.Audit.list(study.id, kind: "agent_output_invalid")
    end

    test "agent-level validation failures are retried too" do
      LLMStub.stub(fn _ -> Jason.encode!(Map.put(@brief, "assumptions", [])) end)
      assert {:error, {:invalid_output, "intake", errors}} = Runner.run(Intake, @input, %{})
      assert Enum.any?(errors, &(&1 =~ "assumptions"))
    end

    test "model errors are returned without retry" do
      LLMStub.stub(fn _ -> {:error, :rate_limited} end)
      assert {:error, {:llm, :rate_limited}} = Runner.run(Intake, @input, %{})
    end
  end

  describe "run_reviewed/4" do
    test "revises once on a Skeptic REVISE, then passes" do
      {:ok, n} = Agent.start_link(fn -> 0 end)

      LLMStub.stub(fn
        %{agent: "skeptic"} ->
          if Agent.get_and_update(n, &{&1, &1 + 1}) == 0,
            do:
              ~s({"verdict":"REVISE","issues":[{"kind":"bias","detail":"too rosy","fix":"tone it down"}]}),
            else: ~s({"verdict":"PASS","issues":[]})

        %{agent: "intake", prompt: prompt} ->
          if prompt =~ "Fix these issues",
            do: Jason.encode!(Map.put(@brief, "what", "revised")),
            else: Jason.encode!(@brief)
      end)

      assert {:ok, %{what: "revised"}, meta} = Runner.run_reviewed(Intake, @input, %{})
      assert meta.review_verdict == "pass"

      assert [%{"source" => "skeptic", "issues" => ["bias: too rosy Fix: tone it down"]}] =
               meta.review_notes["revisions"]
    end

    test "keeps the output marked revise when revisions run out" do
      LLMStub.stub(fn
        %{agent: "skeptic"} -> ~s({"verdict":"REVISE","issues":[{"kind":"other","detail":"meh"}]})
        _ -> Jason.encode!(@brief)
      end)

      assert {:ok, _, %{review_verdict: "revise", review_notes: notes}} =
               Runner.run_reviewed(Intake, @input, %{}, max_revisions: 0)

      assert [%{"detail" => "meh"}] = notes["issues"]
    end

    test "unreferenced claims block the output" do
      study = study_fixture()
      obs = observation_fixture(study)

      positioning = fn refs ->
        Jason.encode!(%{
          "alternatives" => ["Spreadsheets"],
          "unique_attributes" => ["fast"],
          "value" => ["saves time"],
          "best_fit_customer" => "designers",
          "market_category" => "GST tools",
          "headline_variants" => ["A", "B"],
          "landing_copy" => %{"headline" => "A"},
          "claims" => [%{"text" => "Designers lose weekends", "evidence_ids" => refs}]
        })
      end

      LLMStub.stub(fn
        %{agent: "skeptic"} -> ~s({"verdict":"PASS","issues":[]})
        _ -> positioning.(["E999999"])
      end)

      assert {:error, {:claim_check, "positioning_writer", [issue]}} =
               Runner.run_reviewed(PositioningWriter, %{}, %{study_id: study.id},
                 evidence_ids: MapSet.new([obs.id])
               )

      assert issue =~ "E999999"
      assert [_] = Atlas.Audit.list(study.id, kind: "claim_check_blocked")

      LLMStub.stub(fn
        %{agent: "skeptic"} -> ~s({"verdict":"PASS","issues":[]})
        _ -> positioning.(["E#{obs.id}"])
      end)

      assert {:ok, _, %{review_verdict: "pass"}} =
               Runner.run_reviewed(PositioningWriter, %{}, %{study_id: study.id},
                 evidence_ids: MapSet.new([obs.id])
               )
    end

    test "banned phrases trigger a rewrite and are noted if they survive" do
      LLMStub.stub(fn
        %{agent: "skeptic"} -> ~s({"verdict":"PASS","issues":[]})
        _ -> Jason.encode!(Map.put(@brief, "what", "A game-changer for GST"))
      end)

      assert {:ok, _, meta} = Runner.run_reviewed(Intake, @input, %{}, banned_phrases: true)
      assert [%{"source" => "gate"}] = meta.review_notes["revisions"]
      assert [note] = meta.review_notes["gate_notes"]
      assert note =~ "game-changer"
    end

    test "a failing Skeptic leaves the review pending instead of blocking" do
      LLMStub.stub(fn
        %{agent: "skeptic"} -> {:error, :timeout}
        _ -> Jason.encode!(@brief)
      end)

      assert {:ok, _, %{review_verdict: "pending", review_notes: %{"gate_notes" => [note]}}} =
               Runner.run_reviewed(Intake, @input, %{})

      assert note =~ "skeptic review failed"
    end

    test "review can be turned off" do
      LLMStub.stub(fn
        %{agent: "skeptic"} -> flunk("skeptic should not run")
        _ -> Jason.encode!(@brief)
      end)

      assert {:ok, _, %{review_verdict: "pending"}} =
               Runner.run_reviewed(Intake, @input, %{}, review: false)
    end
  end

  test "Skeptic normalises verdict case and needs issues for REVISE" do
    LLMStub.stub(fn _ -> ~s({"verdict":"pass"}) end)
    assert {:ok, %{verdict: "PASS"}, _} = Runner.run(Skeptic, %{kind: "x", output: %{}}, %{})

    LLMStub.stub(fn _ -> ~s({"verdict":"REVISE","issues":[]}) end)

    assert {:error, {:invalid_output, "skeptic", _}} =
             Runner.run(Skeptic, %{kind: "x", output: %{}}, %{})
  end
end
