defmodule Atlas.StudyLoopTest do
  @moduledoc """
  End-to-end study loop on the mock adapter (the M1–M4 demo gates in CI):
  intake → segments → prune → desk research → desk score → experiment design
  → approval locks thresholds → upload → ingest → verdict → next loop.
  """
  use Atlas.DataCase, async: false

  import Atlas.{Fixtures, StudyHelpers}

  alias Atlas.{Approvals, Artifacts, Evidence, Experiments, Studies, Study}

  setup do
    on_exit(&stop_all_studies/0)
    :ok
  end

  test "runs a full loop and loops back" do
    {:ok, study} =
      Study.start(%{
        name: "LedgerLite",
        description: "AI bookkeeping for Indian freelancers that prepares GST returns.",
        adapter: "mock",
        budget: 150
      })

    # 1–2. Intake, then the strategist proposes segments and the study waits.
    study = await_state(study.id, "hypothesize")
    assert Artifacts.latest(study.id, "brief")
    proposed = Studies.list_segments(study.id, status: "proposed")
    assert length(proposed) == 4
    assert length(Studies.list_hypotheses(study.id)) == 4

    # Events that don't fit the state are refused.
    assert {:error, {:not_allowed, "hypothesize", :finish_data}} =
             Study.finish_data_collection(study.id)

    # Human prunes to two.
    [a, b | _] = proposed
    assert :ok = Study.prune_segments(study.id, [a.id, b.id])

    # 3–5. Desk research, desk score, positioning, experiment design.
    study = await_state(study.id, "await_data")

    assert Enum.map(Studies.list_segments(study.id, status: "kept"), & &1.id) |> Enum.sort() ==
             Enum.sort([a.id, b.id])

    assert length(Studies.list_segments(study.id, status: "pruned")) == 2

    by_type = Evidence.counts_by_type(study.id)
    assert by_type["desk"] > 0
    assert by_type["voc"] > 0
    refute Map.has_key?(by_type, "experimental")

    desk = Artifacts.latest(study.id, "scorecard")
    assert desk.body["stage"] == "desk"
    # Desk evidence alone can never reach approaching_fit or fit.
    assert Enum.all?(desk.body["segments"], &(&1["verdict"] in ["no_signal", "promising"]))
    assert Artifacts.latest(study.id, "competitor_map")
    assert length(Artifacts.list(study.id, kind: "positioning")) == 2

    experiments = Experiments.list(study.id)
    assert length(experiments) == 2
    assert Enum.all?(experiments, &(&1.status == "draft"))

    # 6. Approving a design locks its thresholds; then results can be uploaded.
    [exp | _] = experiments

    survey_artifact =
      Enum.find(Artifacts.list(study.id, kind: "survey"), &(&1.experiment_id == exp.id))

    assert {:error, :not_locked} =
             Experiments.upload_result(exp, "survey_csv", tmp_file("s.csv", survey_csv()))

    assert {:ok, _, _} = Approvals.decide(survey_artifact.id, "approved", nil)

    exp = Experiments.get!(exp.id)
    assert exp.status == "locked"

    assert {:error, :thresholds_locked} =
             Experiments.edit(exp, %{"thresholds" => %{"criteria" => []}})

    assert {:error, :no_results_uploaded} = Study.finish_data_collection(study.id)

    assert {:ok, _} =
             Experiments.upload_result(exp, "survey_csv", tmp_file("s.csv", survey_csv(30, 5, 5)))

    assert {:ok, _} =
             Experiments.upload_result(exp, "transcript", tmp_file("t.txt", transcript()))

    # 7–8. Ingest and verdict.
    assert :ok = Study.finish_data_collection(study.id)
    study = await_state(study.id, "verdict")

    exp = Experiments.get!(exp.id)
    assert exp.status == "completed"
    assert exp.outcome == "passed"
    assert Studies.get_hypothesis!(exp.hypothesis_id).status == "supported"

    se = Evidence.list(study.id, signal_code: "sean_ellis_very_disappointed_pct")
    assert [%{value_num: 75.0, evidence_type: "experimental"}] = se

    verdict = Artifacts.latest(study.id, "scorecard")
    assert verdict.body["stage"] == "verdict"
    assert study.verdict in Atlas.Studies.Study.verdicts()
    assert study.next_move in Atlas.Studies.Study.next_moves()

    # Transcripts are stored redacted.
    [transcript_result] =
      Experiments.list_results(exp.id) |> Enum.filter(&(&1.kind == "transcript"))

    {:ok, stored} = Experiments.read_upload(transcript_result)
    refute stored =~ "priya@example.com"
    assert stored =~ "[EMAIL]"

    # Next loop goes where the deterministic route sends it.
    assert :ok = Study.continue(study.id, "design_tests")
    study = await_state(study.id, "await_data")
    assert study.loop_number == 2

    # Every model call was recorded against the budget.
    study = Studies.get_study!(study.id)
    assert study.calls_used > 10
    assert study.calls_used <= study.budget
    assert length(Atlas.Usage.by_agent(study.id)) >= 8

    assert :ok = Study.close(study.id)
    assert Studies.get_study!(study.id).state == "closed"
    assert {:error, :closed} = Study.retry(study.id)
  end

  test "re-segmenting after a pivot proposes new segments in a new loop" do
    {:ok, study} =
      Study.start(%{name: "X", description: "A product for testing pivots.", adapter: "mock"})

    study = await_state(study.id, "hypothesize")
    [a | _] = Studies.list_segments(study.id, status: "proposed")
    :ok = Study.prune_segments(study.id, [a.id])
    study = await_state(study.id, "await_data")

    [exp] = Experiments.list(study.id)
    artifact = Enum.find(Artifacts.list(study.id), &(&1.experiment_id == exp.id))
    {:ok, _, _} = Approvals.decide(artifact.id, "approved", nil)

    {:ok, _} =
      Experiments.upload_result(
        Experiments.get!(exp.id),
        "survey_csv",
        tmp_file("s.csv", survey_csv(1, 2, 30))
      )

    :ok = Study.finish_data_collection(study.id)
    study = await_state(study.id, "verdict")
    assert Experiments.get!(exp.id).outcome == "failed"

    :ok = Study.continue(study.id, "hypothesize")
    study = await_state(study.id, "hypothesize")
    assert study.loop_number == 2
    assert length(Studies.list_segments(study.id, status: "proposed", loop: 2)) == 4
  end
end
