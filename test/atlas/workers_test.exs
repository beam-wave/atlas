defmodule Atlas.WorkersTest do
  use Atlas.DataCase, async: false
  use Oban.Testing, repo: Atlas.Repo, engine: Oban.Engines.Lite

  import Atlas.Fixtures

  alias Atlas.{Artifacts, Evidence, Experiments, Studies}
  alias Atlas.Workers.{Analyst, Reminder, Reobserve, Rescore}

  defp study_with_kept_segment(state \\ "await_data") do
    study = study_fixture()
    seg = segment_fixture(study)
    observation_fixture(study, %{segment_id: seg.id})
    {:ok, study} = Studies.update_study(study, %{state: state})
    {study, seg}
  end

  test "Rescore writes a new scorecard" do
    {study, _} = study_with_kept_segment()
    assert :ok = perform_job(Rescore, %{study_id: study.id})

    assert %{body: %{"stage" => "rescore", "segments" => [_]}} =
             Artifacts.latest(study.id, "scorecard")

    assert Studies.get_study!(study.id).verdict
  end

  test "Rescore skips studies that cannot be scored yet" do
    {study, _} = study_with_kept_segment("hypothesize")
    assert {:cancel, :study_not_scorable} = perform_job(Rescore, %{study_id: study.id})
  end

  test "Reobserve adds fresh desk and voc evidence and queues a re-score" do
    {study, _} = study_with_kept_segment()
    before = Evidence.count(study.id)
    assert :ok = perform_job(Reobserve, %{study_id: study.id})
    assert Evidence.count(study.id) > before
    assert_enqueued(worker: Rescore, args: %{study_id: study.id})
  end

  test "Reminder nudges studies with stale experiments" do
    {study, _} = study_with_kept_segment()
    exp = locked_experiment_fixture(study)
    stale = DateTime.add(DateTime.utc_now(:second), -10 * 86_400)
    Repo.update!(Ecto.Changeset.change(exp, locked_at: stale))

    Studies.subscribe(study.id)
    assert :ok = perform_job(Reminder, %{})

    assert [%{payload: %{"experiments_without_results" => ["Sean Ellis survey"]}}] =
             Atlas.Audit.list(study.id, kind: "reminder")

    assert_receive {:study_event, _, {:reminder, _}}
  end

  test "Analyst turns recurring rejection notes into proposals in the queue" do
    study = study_fixture()

    for note <- ["Too much jargon", "Jargon again"] do
      {:ok, a} = Artifacts.create(%{study_id: study.id, kind: "positioning", body: %{}})
      {:ok, _} = Artifacts.decide(a, "rejected", note, "me")
    end

    assert :ok = perform_job(Analyst, %{study_id: study.id})

    assert [
             %{
               kind: "skill_edit_proposal",
               status: "pending_approval",
               body: %{"skill" => "clear_writing"}
             }
           ] =
             Artifacts.list(study.id, kind: "skill_edit_proposal")
  end

  test "Analyst waits for a pattern" do
    study = study_fixture()
    assert {:cancel, :not_enough_notes} = perform_job(Analyst, %{study_id: study.id})
  end

  test "results ingest without the coordinator through Experiments" do
    {study, seg} = study_with_kept_segment()
    exp = locked_experiment_fixture(study, %{segment_id: seg.id})

    {:ok, _} =
      Experiments.upload_result(exp, "survey_csv", tmp_file("s.csv", survey_csv(5, 0, 0)))

    assert :ok = Atlas.Study.Steps.ready_for_ingest(study)
  end
end
