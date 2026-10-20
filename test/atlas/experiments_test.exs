defmodule Atlas.ExperimentsTest do
  use Atlas.DataCase, async: false

  import Atlas.Fixtures

  alias Atlas.Experiments
  alias Atlas.Experiments.Evaluator

  describe "Evaluator" do
    @t %{
      "criteria" => [
        %{"metric" => "a", "operator" => ">=", "value" => 40},
        %{"metric" => "b", "operator" => "<", "value" => 10}
      ],
      "min_sample" => 20
    }

    test "passes when every criterion is met" do
      assert {"passed", checks} =
               Evaluator.evaluate(@t, %{"a" => 40, "b" => 9, "sample_size" => 20})

      assert Enum.all?(checks, &(&1["result"] == "met"))
    end

    test "fails when a criterion is missed" do
      assert {"failed", _} = Evaluator.evaluate(@t, %{"a" => 39.9, "b" => 9, "sample_size" => 50})
    end

    test "is inconclusive with a small sample or a missing metric" do
      assert {"inconclusive", _} =
               Evaluator.evaluate(@t, %{"a" => 90, "b" => 1, "sample_size" => 5})

      assert {"inconclusive", _} = Evaluator.evaluate(@t, %{"a" => 90, "sample_size" => 50})
      assert {"inconclusive", _} = Evaluator.evaluate(@t, %{"a" => 90, "b" => 1})
    end

    test "supports every operator" do
      for {op, v, expected} <- [
            {">", 4, "passed"},
            {"<=", 5, "passed"},
            {"==", 5, "passed"},
            {"<", 5, "failed"}
          ] do
        t = %{"criteria" => [%{"metric" => "m", "operator" => op, "value" => v}]}
        assert {^expected, _} = Evaluator.evaluate(t, %{"m" => 5})
      end
    end
  end

  describe "create/1" do
    test "validates thresholds" do
      study = study_fixture()
      base = %{study_id: study.id, kind: "interview", title: "T", design: %{"questions" => ["q"]}}

      assert {:error, cs} = Experiments.create(Map.put(base, :thresholds, %{"criteria" => []}))
      assert "needs at least one criterion" in errors_on(cs).thresholds

      assert {:error, cs} =
               Experiments.create(
                 Map.put(base, :thresholds, %{
                   "criteria" => [%{"metric" => "x", "operator" => "~", "value" => 1}]
                 })
               )

      assert [msg] = errors_on(cs).thresholds
      assert msg =~ "operator"
    end

    test "lints surveys before saving" do
      study = study_fixture()

      assert {:error, {:survey_lint, _}} =
               Experiments.create(%{
                 study_id: study.id,
                 kind: "survey",
                 title: "Bad",
                 design: %{"questions" => [%{"text" => "Would you buy this?"}]},
                 thresholds: %{
                   "criteria" => [%{"metric" => "responses", "operator" => ">=", "value" => 1}]
                 }
               })
    end
  end

  describe "locking and uploads" do
    test "edits work until locked; uploads only after" do
      study = study_fixture()
      exp = experiment_fixture(study)
      {:ok, exp} = Experiments.edit(exp, %{"title" => "Renamed"})
      assert exp.title == "Renamed"

      assert {:error, :not_locked} =
               Experiments.upload_result(
                 exp,
                 "survey_csv",
                 tmp_file("s.csv", survey_csv(1, 1, 1))
               )

      {:ok, exp} = Experiments.lock(exp)
      assert exp.locked_at
      assert {:ok, ^exp} = Experiments.lock(exp)

      assert {:error, :thresholds_locked} =
               Experiments.edit(exp, %{"thresholds" => %{"criteria" => []}})

      {:ok, result} =
        Experiments.upload_result(exp, "survey_csv", tmp_file("s.csv", survey_csv(1, 1, 1)))

      assert result.summary["metrics"]["responses"] == 3
      assert {:ok, body} = Experiments.read_upload(result)
      assert body =~ "Very disappointed"

      assert [%{kind: "thresholds_locked"}] =
               Atlas.Audit.list(study.id, kind: "thresholds_locked")

      assert [%{kind: "result_uploaded"}] = Atlas.Audit.list(study.id, kind: "result_uploaded")

      {:ok, done} = Experiments.complete(Experiments.get!(exp.id), "passed")

      assert {:error, :experiment_completed} =
               Experiments.upload_result(
                 done,
                 "survey_csv",
                 tmp_file("s.csv", survey_csv(1, 1, 1))
               )
    end

    test "bad uploads are refused without storing anything" do
      study = study_fixture()
      exp = locked_experiment_fixture(study)

      assert {:error, :no_responses} =
               Experiments.upload_result(exp, "survey_csv", tmp_file("s.csv", "a\n"))

      assert Experiments.list_results(exp.id) == []
    end

    test "uploads are stored under a sanitised filename and deleted with the study" do
      study = study_fixture()
      exp = locked_experiment_fixture(study)

      {:ok, r} =
        Experiments.upload_result(exp, "transcript", tmp_file("t.txt", transcript()),
          filename: "../../etc/pass wd.txt"
        )

      refute r.raw_upload_ref =~ ".."
      assert r.raw_upload_ref =~ "pass_wd.txt"

      Experiments.delete_uploads(study.id)
      assert {:error, :enoent} = Experiments.read_upload(r)
    end
  end
end
