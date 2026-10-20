defmodule Atlas.ScoringTest do
  use ExUnit.Case, async: true

  alias Atlas.Evidence.Observation
  alias Atlas.Scoring

  defp obs(id, type, code \\ "note", num \\ nil),
    do: %Observation{id: id, evidence_type: type, signal_code: code, value_num: num}

  defp r(dim, score, type),
    do: %{"dimension" => dim, "score" => score * 1.0, "evidence_type" => type}

  describe "sean_ellis_score/1" do
    test "maps percentages to the rubric bands" do
      assert Scoring.sean_ellis_score(40.0) == 5
      assert Scoring.sean_ellis_score(39.9) == 4
      assert Scoring.sean_ellis_score(30) == 4
      assert Scoring.sean_ellis_score(20) == 3
      assert Scoring.sean_ellis_score(10) == 2
      assert Scoring.sean_ellis_score(1) == 1
      assert Scoring.sean_ellis_score(0) == 0
      assert Scoring.sean_ellis_score(nil) == nil
    end
  end

  describe "retention_score/2" do
    test "rewards flattening curves" do
      assert Scoring.retention_score(45, true) == 5
      assert Scoring.retention_score(25, true) == 4
      assert Scoring.retention_score(10, true) == 3
      assert Scoring.retention_score(25, false) == 2
      assert Scoring.retention_score(5, false) == 1
    end
  end

  describe "composite/1" do
    test "matches the pmf_scorecard skill's worked example (round 1: 42.1)" do
      ratings = [
        r("problem_intensity", 4, "voc"),
        r("willingness_to_pay", 2, "desk"),
        r("reachability", 3, "desk"),
        r("competitive_gap", 3, "desk")
      ]

      assert Scoring.composite(ratings) == 42.1
    end

    test "matches the worked example (round 2: 66.4)" do
      ratings = [
        r("problem_intensity", 4, "voc"),
        r("willingness_to_pay", 3, "experimental"),
        r("reachability", 4, "experimental"),
        r("competitive_gap", 3, "desk"),
        r("sean_ellis", 5, "experimental"),
        r("retention", 3, "experimental")
      ]

      assert Scoring.composite(ratings) == 66.4
      assert {"approaching_fit", nil} = Scoring.verdict(ratings, 41.0)
    end

    test "is nil with no ratings" do
      assert Scoring.composite([]) == nil
    end

    test "desk-only perfect scores cap at 60" do
      ratings =
        for d <- ~w(problem_intensity willingness_to_pay reachability competitive_gap),
            do: r(d, 5, "desk")

      assert Scoring.composite(ratings) == 60.0
    end
  end

  describe "verdict/2" do
    test "fit needs Sean Ellis >= 40, retention >= 4 and composite >= 70" do
      ratings = [
        r("problem_intensity", 5, "experimental"),
        r("willingness_to_pay", 4, "experimental"),
        r("sean_ellis", 5, "experimental"),
        r("retention", 4, "experimental")
      ]

      assert {"fit", nil} = Scoring.verdict(ratings, 45.0)
      assert {"approaching_fit", nil} = Scoring.verdict(ratings, 39.0)
    end

    test "no_signal below 40 and promising from 40" do
      assert {"no_signal", _} = Scoring.verdict([r("problem_intensity", 1, "desk")], nil)
      assert {"promising", _} = Scoring.verdict([r("problem_intensity", 5, "voc")], nil)
    end

    test "approaching_fit needs experimental evidence in two dimensions" do
      ratings = [r("problem_intensity", 5, "experimental"), r("reachability", 5, "voc")]
      refute elem(Scoring.verdict(ratings, nil), 0) == "approaching_fit"
    end
  end

  describe "normalize_ratings/2" do
    test "sets evidence type from what is actually cited" do
      observations = [obs(1, "desk"), obs(2, "voc"), obs(3, "experimental")]

      [rating] =
        Scoring.normalize_ratings(
          [
            %{
              "dimension" => "problem_intensity",
              "score" => 4,
              "evidence_type" => "experimental",
              "evidence_ids" => ["E1", "E2"]
            }
          ],
          observations
        )

      assert rating["evidence_type"] == "voc"
      assert rating["score"] == 4.0
    end

    test "drops uncited, unknown-evidence, out-of-range and code-only ratings" do
      observations = [obs(1, "desk")]

      proposed = [
        %{"dimension" => "problem_intensity", "score" => 4, "evidence_ids" => []},
        %{"dimension" => "reachability", "score" => 4, "evidence_ids" => ["E99"]},
        %{"dimension" => "competitive_gap", "score" => 7, "evidence_ids" => ["E1"]},
        %{"dimension" => "sean_ellis", "score" => 5, "evidence_ids" => ["E1"]},
        %{"dimension" => "made_up", "score" => 3, "evidence_ids" => ["E1"]},
        %{"dimension" => "willingness_to_pay", "score" => 2, "evidence_ids" => ["E1"]}
      ]

      assert [%{"dimension" => "willingness_to_pay"}] =
               Scoring.normalize_ratings(proposed, observations)
    end
  end

  describe "experimental_ratings/1" do
    test "computes Sean Ellis and retention from the latest experimental rows" do
      observations = [
        obs(1, "experimental", "sean_ellis_very_disappointed_pct", 20.0),
        obs(2, "experimental", "sean_ellis_very_disappointed_pct", 42.0),
        obs(3, "experimental", "retention_pct", 30.0),
        obs(4, "experimental", "retention_flattening", 1.0),
        obs(5, "desk", "sean_ellis_very_disappointed_pct", 90.0)
      ]

      ratings = Scoring.experimental_ratings(observations)

      assert %{"score" => 5.0, "evidence_ids" => ["E2"]} =
               Enum.find(ratings, &(&1["dimension"] == "sean_ellis"))

      assert %{"score" => 4.0} = Enum.find(ratings, &(&1["dimension"] == "retention"))
    end

    test "returns nothing without experimental data" do
      assert Scoring.experimental_ratings([obs(1, "desk", "retention_pct", 50.0)]) == []
    end
  end

  describe "score_segment/2" do
    test "the verdict guard caps desk/voc evidence at promising" do
      observations = [obs(1, "voc"), obs(2, "desk")]

      proposed =
        for d <- ~w(problem_intensity willingness_to_pay reachability competitive_gap),
            do: %{"dimension" => d, "score" => 5, "evidence_ids" => ["E1"]}

      card = Scoring.score_segment(proposed, observations)
      assert card["composite"] == 80.0
      assert card["verdict"] == "promising"
      assert card["evidence_types"] == ["voc"]
    end

    test "counts dropped model ratings" do
      card =
        Scoring.score_segment(
          [%{"dimension" => "reachability", "score" => 3, "evidence_ids" => []}],
          []
        )

      assert card["dropped"] == 1
      assert card["composite"] == nil
      assert card["verdict"] == "no_signal"
    end
  end

  describe "next_move/2 and route/1" do
    test "follows the decision framework" do
      assert Scoring.next_move("approaching_fit", []) == "double_down"

      assert Scoring.next_move("promising", [
               r("problem_intensity", 4, "voc"),
               r("willingness_to_pay", 4, "voc")
             ]) == "double_down"

      assert Scoring.next_move("promising", [
               r("problem_intensity", 4, "voc"),
               r("competitive_gap", 1, "desk")
             ]) == "reposition"

      assert Scoring.next_move("no_signal", [r("problem_intensity", 1, "experimental")]) ==
               "pivot"

      # Never pivot on desk evidence alone.
      assert Scoring.next_move("no_signal", [r("problem_intensity", 1, "desk")]) == "double_down"

      assert Scoring.next_move("promising", [
               r("problem_intensity", 3, "voc"),
               r("reachability", 3, "experimental")
             ]) == "narrow"

      assert Scoring.next_move("promising", [r("problem_intensity", 3, "voc")]) == "double_down"
    end

    test "routes pivots and repositions to re-segmentation" do
      assert Scoring.route("pivot") == "hypothesize"
      assert Scoring.route("reposition") == "hypothesize"
      assert Scoring.route("narrow") == "design_tests"
      assert Scoring.route("double_down") == "design_tests"
    end
  end
end
