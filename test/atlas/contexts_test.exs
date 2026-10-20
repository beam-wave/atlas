defmodule Atlas.ContextsTest do
  use Atlas.DataCase, async: false

  import Atlas.Fixtures

  alias Atlas.{Approvals, Artifacts, Evidence, Experiments, Studies}
  alias Atlas.Evidence.{Observation, SignalCodes}

  describe "Studies" do
    test "create_study validates product and study together" do
      assert {:error, cs} = Studies.create_study(%{name: "", description: "short"})
      assert %{name: [_], description: [_]} = errors_on(cs)

      assert {:error, cs} =
               Studies.create_study(%{name: "X", description: "Long enough text", url: "ftp://x"})

      assert %{url: [_]} = errors_on(cs)

      assert {:error, cs} =
               Studies.create_study(%{
                 name: "X",
                 description: "Long enough text",
                 adapter: "skynet"
               })

      assert %{adapter: ["is not a known adapter"]} = errors_on(cs)
      assert Repo.aggregate(Atlas.Studies.Product, :count) == 0

      study = study_fixture(%{budget: 40})
      assert study.state == "intake"
      assert study.budget == 40
      assert study.product.name == "LedgerLite"
    end

    test "prune keeps the chosen proposed segments and prunes the rest" do
      study = study_fixture()
      a = segment_fixture(study, %{status: "proposed"})
      b = segment_fixture(study, %{status: "proposed"})

      assert {:error, :nothing_kept} = Studies.prune_segments(study.id, [999])
      assert {:ok, 1} = Studies.prune_segments(study.id, [to_string(a.id)])
      assert Studies.get_segment!(a.id).status == "kept"
      assert Studies.get_segment!(b.id).status == "pruned"
    end

    test "consume_call is atomic against the budget" do
      study = study_fixture(%{budget: 3})

      results =
        1..10
        |> Task.async_stream(fn _ -> Studies.consume_call(study.id) end, max_concurrency: 10)
        |> Enum.map(fn {:ok, r} -> r end)

      assert Enum.count(results, &(&1 == :ok)) == 3
      assert Studies.get_study!(study.id).calls_used == 3
    end

    test "updates broadcast to subscribers" do
      study = study_fixture()
      Studies.subscribe(study.id)
      {:ok, _} = Studies.update_study(study, %{state: "hypothesize"})
      assert_receive {:study_event, _, {:updated, %{state: "hypothesize"}}}
      assert {:error, _} = Studies.update_study(study, %{state: "dancing"})
    end
  end

  describe "Evidence" do
    test "rejects codes outside the governed vocabulary at the database" do
      study = study_fixture()

      assert {:error, cs} =
               Evidence.record(%{
                 study_id: study.id,
                 signal_code: "vibes",
                 value_num: 1,
                 evidence_type: "desk",
                 confidence: 0.5,
                 source_note: "x"
               })

      assert %{signal_code: ["is not in the governed vocabulary"]} = errors_on(cs)

      # Even bypassing the changeset, the foreign key rejects it.
      now = DateTime.utc_now(:second)

      assert_raise Exqlite.Error, ~r/FOREIGN KEY/, fn ->
        Repo.insert_all("observations", [
          %{
            study_id: study.id,
            signal_code: "vibes",
            value_num: 1.0,
            evidence_type: "desk",
            confidence: 0.5,
            observed_at: now,
            loop_number: 1,
            inserted_at: now,
            updated_at: now
          }
        ])
      end
    end

    test "requires a source for desk and voc, a value, and a sane confidence" do
      study = study_fixture()

      base = %{
        study_id: study.id,
        signal_code: "note",
        value_text: "x",
        evidence_type: "desk",
        confidence: 0.5
      }

      assert {:error, cs} = Evidence.record(base)
      assert %{source_url: [_]} = errors_on(cs)
      assert {:ok, _} = Evidence.record(%{base | evidence_type: "experimental"})

      assert {:error, cs} =
               Evidence.record(%{base | evidence_type: "experimental", confidence: 1.5})

      assert %{confidence: [_]} = errors_on(cs)

      assert {:error, cs} =
               Evidence.record(%{base | evidence_type: "experimental", value_text: nil})

      assert %{value_num: [_]} = errors_on(cs)

      assert {:error, cs} =
               Evidence.record(Map.merge(base, %{evidence_type: "rumour", source_note: "x"}))

      assert %{evidence_type: [_]} = errors_on(cs)
    end

    test "record_many is all-or-nothing" do
      study = study_fixture()

      good = %{
        study_id: study.id,
        signal_code: "note",
        value_text: "x",
        evidence_type: "experimental",
        confidence: 0.5
      }

      assert {:error, {1, _}} = Evidence.record_many([good, %{good | signal_code: "vibes"}])
      assert Evidence.count(study.id) == 0
      assert {:ok, [_, _]} = Evidence.record_many([good, good])
    end

    test "filters, digests and refs" do
      study = study_fixture()
      seg = segment_fixture(study)
      o1 = observation_fixture(study, %{segment_id: seg.id})
      o2 = observation_fixture(study)

      _o3 =
        observation_fixture(study, %{
          evidence_type: "desk",
          signal_code: "market_size",
          value_num: 10.0,
          value_text: nil
        })

      assert [^o1] = Evidence.list(study.id, segment_id: seg.id) |> Enum.map(&Repo.reload/1)
      assert length(Evidence.list(study.id, segment_id: seg.id, include_study_wide: true)) == 3
      assert length(Evidence.list(study.id, evidence_type: "voc")) == 2
      assert Evidence.counts_by_type(study.id) == %{"voc" => 2, "desk" => 1}

      assert MapSet.equal?(
               Evidence.ids(study.id),
               MapSet.new(Enum.map(Evidence.list(study.id), & &1.id))
             )

      [d | _] = Evidence.digest([o2])
      assert d["ref"] == "E#{o2.id}"
      assert d["source"] == "https://example.com/thread"

      assert Observation.parse_ref("E12") == {:ok, 12}
      assert Observation.parse_ref("E1x") == :error
      assert Observation.parse_ref(12) == :error
    end

    test "the vocabulary covers every scoring dimension" do
      for dim <- SignalCodes.scoring_dimensions(), do: assert(SignalCodes.codes_for(dim) != [])
      assert SignalCodes.dimension("pain_quote") == "problem_intensity"
      assert SignalCodes.dimension("nope") == nil
    end
  end

  describe "Artifacts and approvals" do
    test "approval kinds start pending; others are final" do
      study = study_fixture()
      {:ok, survey} = Artifacts.create(%{study_id: study.id, kind: "survey", body: %{}})
      {:ok, brief} = Artifacts.create(%{study_id: study.id, kind: "brief", body: %{}})
      assert survey.status == "pending_approval"
      assert brief.status == "final"
      assert Enum.map(Artifacts.approval_queue(), & &1.id) == [survey.id]
      assert Artifacts.pending_count(study.id) == 1
    end

    test "a rejection needs a reason; a decision can be made once" do
      study = study_fixture()
      {:ok, a} = Artifacts.create(%{study_id: study.id, kind: "positioning", body: %{}})

      assert {:error, cs} = Approvals.decide(a.id, "rejected", "  ")
      assert %{note: ["is required when rejecting"]} = errors_on(cs)
      assert Artifacts.get!(a.id).status == "pending_approval"

      assert {:ok, %{status: "rejected"}, %{note: "Too vague"}} =
               Approvals.decide(a.id, "rejected", "Too vague")

      assert {:error, :not_pending} = Approvals.decide(a.id, "approved", nil)
      assert [%{note: "Too vague", kind: "positioning"}] = Artifacts.rejection_notes()
    end

    test "approving an experiment design locks it; rejecting cancels it and queues the analyst" do
      study = study_fixture()
      exp = experiment_fixture(study)
      exp2 = experiment_fixture(study)

      {:ok, a} =
        Artifacts.create(%{study_id: study.id, kind: "survey", experiment_id: exp.id, body: %{}})

      {:ok, b} =
        Artifacts.create(%{study_id: study.id, kind: "survey", experiment_id: exp2.id, body: %{}})

      {:ok, _, _} = Approvals.decide(a.id, "approved", nil, "sumit")
      assert %{status: "locked", locked_at: %DateTime{}} = Experiments.get!(exp.id)

      {:ok, _, _} = Approvals.decide(b.id, "rejected", "Leading question 3")
      assert Experiments.get!(exp2.id).status == "cancelled"
      assert [%Oban.Job{worker: "Atlas.Workers.Analyst"}] = all_enqueued_jobs()
    end

    test "approving a skill edit appends it to the skill" do
      study = study_fixture()
      {:ok, skill} = Atlas.Skills.Library.get("guardrails")
      original = File.read!(skill.path)

      on_exit(fn ->
        File.write!(skill.path, original)
        Atlas.Skills.Library.reload()
      end)

      {:ok, p} =
        Artifacts.create(%{
          study_id: study.id,
          kind: "skill_edit_proposal",
          body: %{"skill" => "guardrails", "addition" => "- Never quote a minor."}
        })

      {:ok, _, _} = Approvals.decide(p.id, "approved", nil)

      content = File.read!(skill.path)
      assert content =~ "## Lessons from reviews"
      assert content =~ "- Never quote a minor."
      assert {:ok, %{body: body}} = Atlas.Skills.Library.get("guardrails")
      assert body =~ "Never quote a minor"
    end

    test "a broken skill edit rolls back the approval" do
      study = study_fixture()

      {:ok, p} =
        Artifacts.create(%{
          study_id: study.id,
          kind: "skill_edit_proposal",
          body: %{"skill" => "ghost", "addition" => "x"}
        })

      assert {:error, {:skill_edit_failed, :not_found}} = Approvals.decide(p.id, "approved", nil)
      assert Artifacts.get!(p.id).status == "pending_approval"
    end
  end

  defp all_enqueued_jobs, do: Repo.all(Oban.Job)
end
