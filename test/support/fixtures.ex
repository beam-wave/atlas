defmodule Atlas.Fixtures do
  @moduledoc "Test data builders."

  alias Atlas.{Evidence, Experiments, Studies}

  def study_fixture(attrs \\ %{}) do
    {:ok, study} =
      attrs
      |> Enum.into(%{
        name: "LedgerLite",
        description:
          "AI bookkeeping for Indian freelancers that prepares GST returns from bank statements.",
        url: "https://ledgerlite.example",
        price: "₹499/month",
        adapter: "mock"
      })
      |> Studies.create_study()

    study
  end

  def segment_fixture(study, attrs \\ %{}) do
    {:ok, segment} =
      attrs
      |> Enum.into(%{
        study_id: study.id,
        name: "Freelance designers #{System.unique_integer([:positive])}",
        status: "kept",
        job_to_be_done: %{"functional" => "File GST"}
      })
      |> Studies.create_segment()

    segment
  end

  def hypothesis_fixture(segment, attrs \\ %{}) do
    {:ok, h} =
      attrs
      |> Enum.into(%{
        study_id: segment.study_id,
        segment_id: segment.id,
        statement: "Designers spend hours on GST",
        falsified_if: "Under 30% report 2+ hours"
      })
      |> Studies.create_hypothesis()

    h
  end

  def observation_fixture(study, attrs \\ %{}) do
    {:ok, obs} =
      attrs
      |> Enum.into(%{
        study_id: study.id,
        signal_code: "pain_quote",
        value_text: "I lose a weekend every quarter",
        evidence_type: "voc",
        confidence: 0.8,
        source_url: "https://example.com/thread"
      })
      |> Evidence.record()

    obs
  end

  def experiment_fixture(study, attrs \\ %{}) do
    {:ok, exp} =
      attrs
      |> Enum.into(%{
        study_id: study.id,
        kind: "survey",
        title: "Sean Ellis survey",
        design: %{
          "questions" => [
            %{
              "text" => "How would you feel if you could no longer use LedgerLite?",
              "type" => "sean_ellis"
            }
          ]
        },
        thresholds: %{
          "criteria" => [
            %{"metric" => "sean_ellis_very_disappointed_pct", "operator" => ">=", "value" => 40}
          ],
          "min_sample" => 5
        }
      })
      |> Experiments.create()

    exp
  end

  def locked_experiment_fixture(study, attrs \\ %{}) do
    {:ok, exp} = study |> experiment_fixture(attrs) |> Experiments.lock()
    exp
  end

  @doc "Writes content to a temp file and returns its path."
  def tmp_file(name, content) do
    dir = Path.join(System.tmp_dir!(), "atlas-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    path = Path.join(dir, name)
    File.write!(path, content)
    path
  end

  def survey_csv(very \\ 6, somewhat \\ 2, not_disappointed \\ 2) do
    header =
      "respondent,How would you feel if you could no longer use LedgerLite?,What is the main benefit you get?\n"

    rows =
      List.duplicate("Very disappointed", very) ++
        List.duplicate("Somewhat disappointed", somewhat) ++
        List.duplicate("Not disappointed", not_disappointed)

    body =
      rows
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {answer, i} ->
        "#{i},#{answer},\"It saves me the quarterly reconciliation weekend, number #{i}\""
      end)

    header <> body <> "\n"
  end

  def transcript do
    """
    Interviewer: When did you last file GST?
    Priya: Last quarter. I spent the whole Sunday matching invoices to bank entries.
    You can reach me at priya@example.com or +91 98765 43210 if you need more.
    Interviewer: What did you use?
    Priya: A spreadsheet my CA gave me. I paid him 3000 once to fix mistakes. I'd switch if something did it for me.
    """
  end
end
