defmodule Atlas.IngestTest do
  use ExUnit.Case, async: true

  import Atlas.Fixtures, only: [tmp_file: 2, survey_csv: 3, transcript: 0]

  alias Atlas.Ingest
  alias Atlas.Ingest.PII

  describe "survey_csv" do
    test "computes Sean Ellis shares and keeps open text" do
      {:ok, summary, _body} = Ingest.parse("survey_csv", tmp_file("s.csv", survey_csv(4, 3, 3)))
      m = summary["metrics"]
      assert m["responses"] == 10
      assert m["sean_ellis_responses"] == 10
      assert m["sean_ellis_very_disappointed_pct"] == 40.0
      assert m["sean_ellis_somewhat_disappointed_pct"] == 30.0
      assert m["sample_size"] == 10

      assert [%{"question" => "What is the main benefit you get?", "answers" => answers}] =
               summary["open_text"]

      assert length(answers) == 10
    end

    test "computes Van Westendorp medians" do
      csv = """
      id,At what price would it be too cheap to trust?,At what price is it a bargain?,At what price is it getting expensive?,At what price is it too expensive to consider?
      1,100,300,600,1000
      2,"₹200",400,700,1200
      3,150,350,650,1100
      """

      {:ok, %{"metrics" => m}, _} = Ingest.parse("survey_csv", tmp_file("vw.csv", csv))
      assert m["vw_too_cheap"] == 150.0
      assert m["vw_bargain"] == 350.0
      assert m["vw_expensive"] == 650.0
      assert m["vw_too_expensive"] == 1100.0
    end

    test "rejects empty surveys and non-text uploads" do
      assert {:error, :no_responses} = Ingest.parse("survey_csv", tmp_file("e.csv", "a,b\n"))

      assert {:error, :not_utf8_text} =
               Ingest.parse("survey_csv", tmp_file("b.csv", <<0xFF, 0xFE, 0x00>>))

      assert {:error, {:unreadable_upload, :enoent}} =
               Ingest.parse("survey_csv", "/nonexistent.csv")

      assert {:error, {:unknown_result_kind, "pdf"}} = Ingest.parse("pdf", tmp_file("x", "x"))
    end
  end

  describe "analytics_csv" do
    test "accepts a metric,value table" do
      csv = "metric,value\nVisits,400\nSignups,22\nSpend,\"1,100\"\n"
      {:ok, %{"metrics" => m}, _} = Ingest.parse("analytics_csv", tmp_file("a.csv", csv))
      assert m["visits"] == 400.0
      assert m["signups"] == 22.0
      assert m["signup_conversion_pct"] == 5.5
      assert m["cost_per_signup"] == 50.0
      assert m["sample_size"] == 400.0
    end

    test "accepts an event log" do
      rows =
        List.duplicate("pageview,ads,0.5", 50) ++
          List.duplicate("signup,ads,0", 5) ++ ["preorder,ads,0"]

      csv = "event,channel,cost\n" <> Enum.join(rows, "\n")
      {:ok, %{"metrics" => m}, _} = Ingest.parse("analytics_csv", tmp_file("a.csv", csv))
      assert m["visits"] == 50
      assert m["signups"] == 5
      assert m["preorders"] == 1
      assert m["signup_conversion_pct"] == 10.0
      assert m["cost_per_signup"] == 5.0
    end

    test "rejects unknown shapes" do
      assert {:error, {:unrecognised_analytics_csv, _}} =
               Ingest.parse("analytics_csv", tmp_file("a.csv", "foo,bar\n1,2\n"))
    end
  end

  describe "retention_csv" do
    test "detects a flattening curve" do
      csv =
        "cohort,period,retained_pct\n" <>
          Enum.map_join([{0, 100}, {1, 60}, {2, 45}, {3, 41}, {4, 40}, {5, 39.5}], "\n", fn {p, v} ->
            "jan,#{p},#{v}"
          end)

      {:ok, %{"metrics" => m, "curve" => curve}, _} =
        Ingest.parse("retention_csv", tmp_file("r.csv", csv))

      assert m["retention_flattening"] == 1
      assert m["retention_final_pct"] == 39.5
      assert length(curve) == 6
    end

    test "detects a decaying curve and averages cohorts" do
      csv = """
      cohort,period,active,cohort_size
      jan,0,100,100
      jan,1,50,100
      jan,2,25,100
      jan,3,10,100
      feb,3,20,100
      """

      {:ok, %{"metrics" => m}, _} = Ingest.parse("retention_csv", tmp_file("r.csv", csv))
      assert m["retention_flattening"] == 0
      assert m["retention_final_pct"] == 15.0
    end

    test "needs period and a retention column" do
      assert {:error, {:unrecognised_retention_csv, _}} =
               Ingest.parse("retention_csv", tmp_file("r.csv", "a,b\n1,2\n"))
    end
  end

  describe "transcript" do
    test "is stored redacted" do
      {:ok, summary, body} = Ingest.parse("transcript", tmp_file("t.txt", transcript()))
      refute body =~ "priya@example.com"
      refute body =~ "98765"
      assert summary["redactions"]["email"] == 1
      assert summary["redactions"]["phone"] == 1
      assert summary["metrics"]["words"] > 20
    end

    test "rejects very short transcripts" do
      assert {:error, :transcript_too_short} =
               Ingest.parse("transcript", tmp_file("t.txt", "hi there"))
    end
  end

  describe "PII.redact/1" do
    test "redacts emails, phones, card numbers and PAN-style ids" do
      {text, counts} =
        PII.redact(
          "Mail a.b@x.io, call +1 (415) 555-0100, card 4111 1111 1111 1111, PAN ABCDE1234F"
        )

      assert text =~ "[EMAIL]"
      assert text =~ "[PHONE]"
      assert text =~ "[CARD]"
      assert text =~ "[ID_NUMBER]"
      assert counts == %{"email" => 1, "phone" => 1, "card" => 1, "id_number" => 1}
    end
  end

  test "median and pct helpers" do
    assert Ingest.median([3, 1, 2]) == 2
    assert Ingest.median([1, 2, 3, 4]) == 2.5
    assert Ingest.median([]) == nil
    assert Ingest.pct(1, 0) == nil
    assert Ingest.to_number("₹1,200") == 1200.0
    assert Ingest.to_number("n/a") == nil
  end
end
