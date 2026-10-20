defmodule Atlas.GatesTest do
  use Atlas.DataCase, async: false

  import Atlas.Fixtures

  alias Atlas.Gates.{BannedPhrases, ClaimCheck, Outbound, SurveyLint, ThresholdLock, VerdictGuard}

  describe "ClaimCheck" do
    test "passes when every claim cites known evidence" do
      output = %{"claims" => [%{"text" => "Pain is weekly", "evidence_ids" => ["E1", "E2"]}]}
      assert :ok = ClaimCheck.check(output, MapSet.new([1, 2]))
    end

    test "blocks uncited claims and unknown evidence ids, anywhere in the output" do
      output = %{
        "landing" => %{"claims" => [%{"text" => "Uncited", "evidence_ids" => []}]},
        "claims" => [%{"text" => "Ghost", "evidence_ids" => ["E9", "nonsense"]}]
      }

      assert {:error, issues} = ClaimCheck.check(output, MapSet.new([1]))
      assert Enum.any?(issues, &(&1 =~ "uncited claim: Uncited"))
      assert Enum.any?(issues, &(&1 =~ ~s("E9")))
      assert Enum.any?(issues, &(&1 =~ ~s("nonsense")))
    end

    test "outputs without claims pass" do
      assert :ok = ClaimCheck.check(%{"summary" => "x"}, MapSet.new())
    end
  end

  describe "SurveyLint" do
    defp lint(questions), do: SurveyLint.check(%{"questions" => questions})

    test "accepts past-behaviour questions and the standard Sean Ellis / Van Westendorp items" do
      assert :ok =
               lint([
                 %{"text" => "When did you last file GST?", "type" => "open"},
                 %{
                   "text" => "How would you feel if you could no longer use LedgerLite?",
                   "type" => "sean_ellis"
                 },
                 %{
                   "text" =>
                     "At what price would you consider it so expensive that you would not buy it?",
                   "type" => "van_westendorp"
                 }
               ])
    end

    test "rejects leading questions" do
      assert {:error, {:survey_lint, [%{"issue" => "leading question"}]}} =
               lint([%{"text" => "Don't you agree that filing GST is painful?", "type" => "open"}])
    end

    test "rejects hypothetical-future questions" do
      assert {:error, {:survey_lint, [issue]}} =
               lint([%{"text" => "Would you pay ₹499 for this?", "type" => "open"}])

      assert issue["issue"] =~ "hypothetical"

      assert {:error, _} =
               lint([%{"text" => "If we built an app, what would it need?", "type" => "open"}])
    end

    test "rejects double-barrelled rating questions" do
      assert {:error, {:survey_lint, [issue]}} =
               lint([
                 %{
                   "text" => "How satisfied are you with the price and speed?",
                   "type" => "rating"
                 }
               ])

      assert issue["issue"] =~ "double-barrelled"
    end

    test "rejects empty surveys and empty questions" do
      assert {:error, {:survey_lint, [%{"issue" => "survey has no questions"}]}} = lint([])
      assert {:error, _} = lint([%{"text" => " "}])
    end
  end

  describe "ThresholdLock" do
    test "allows edits before locking and refuses (and logs) them after" do
      study = study_fixture()
      exp = experiment_fixture(study)
      assert :ok = ThresholdLock.check_edit(exp, %{"thresholds" => %{}})
      assert {:error, :not_locked} = ThresholdLock.check_upload(exp)

      exp = locked_experiment_fixture(study)
      assert {:error, :thresholds_locked} = ThresholdLock.check_edit(exp, %{thresholds: %{}})
      assert :ok = ThresholdLock.check_edit(exp, %{"title" => "Renamed"})
      assert :ok = ThresholdLock.check_upload(exp)

      assert [%{kind: "threshold_edit_refused"}] =
               Atlas.Audit.list(study.id, kind: "threshold_edit_refused")
    end
  end

  describe "VerdictGuard" do
    test "caps strong verdicts without experimental evidence" do
      assert {"promising", note} = VerdictGuard.apply("fit", ["desk", "voc"])
      assert note =~ "experimental"
      assert {"approaching_fit", nil} = VerdictGuard.apply("approaching_fit", ["experimental"])
      assert {"no_signal", nil} = VerdictGuard.apply("no_signal", [])
    end
  end

  describe "BannedPhrases" do
    test "finds phrases from the clear_writing skill as whole words" do
      phrases = BannedPhrases.phrases()
      assert "game-changer" in phrases

      assert {:error, ["game-changer"]} =
               BannedPhrases.check(%{"copy" => ["A real game-changer for you"]}, ["game-changer"])

      assert :ok = BannedPhrases.check(%{"copy" => "Unlocked doors"}, ["unlock"])
      assert {:error, _} = BannedPhrases.check("Unlock your weekends", ["unlock"])
    end
  end

  describe "Outbound" do
    test "only approved approval-kind artifacts may leave" do
      study = study_fixture()
      {:ok, survey} = Atlas.Artifacts.create(%{study_id: study.id, kind: "survey", body: %{}})
      {:ok, brief} = Atlas.Artifacts.create(%{study_id: study.id, kind: "brief", body: %{}})

      assert {:error, :not_approved} = Outbound.authorize(survey)
      assert :ok = Outbound.authorize(brief)
      assert :ok = Outbound.authorize(%{survey | status: "approved"})
    end
  end
end
