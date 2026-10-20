defmodule AtlasWeb.LiveTest do
  use AtlasWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Atlas.{Fixtures, StudyHelpers}

  alias Atlas.{Artifacts, Experiments, Settings, Studies}

  setup do
    on_exit(fn ->
      if Settings.kill_switch?(), do: Settings.release_kill_switch()
      stop_all_studies()
    end)
  end

  describe "studies page" do
    test "starts a study from the form and lands on it", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/")
      assert html =~ "No studies yet"

      {:ok, _show, html} =
        view
        |> form("#new-study",
          study: %{
            name: "LedgerLite",
            description: "AI bookkeeping for Indian freelancers.",
            adapter: "mock"
          }
        )
        |> render_submit()
        |> follow_redirect(conn)

      assert html =~ "LedgerLite"
      [study] = Studies.list_studies()
      await_state(study.id, "hypothesize")

      {:ok, _view, html} = live(conn, ~p"/")
      assert html =~ "LedgerLite"
      assert html =~ "Hypothesize"
    end

    test "shows validation errors", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/")

      html =
        view |> form("#new-study", study: %{name: "", description: "short"}) |> render_submit()

      assert html =~ "can&#39;t be blank"
      assert Studies.list_studies() == []
    end

    test "sets the default backend", %{conn: conn} do
      on_exit(fn -> Settings.put("default_adapter", nil) end)
      {:ok, view, _} = live(conn, ~p"/")
      view |> element("#default-adapter") |> render_change(%{adapter: "codex_cli"})
      assert Settings.get("default_adapter") == "codex_cli"
    end
  end

  describe "study page" do
    test "walks a study from pruning through upload to verdict", %{conn: conn} do
      {:ok, study} =
        Atlas.Study.start(%{
          name: "LedgerLite",
          description: "AI bookkeeping for freelancers.",
          adapter: "mock"
        })

      await_state(study.id, "hypothesize")

      {:ok, view, html} = live(conn, ~p"/studies/#{study.id}")
      assert html =~ "Choose which segments to research"
      [a | _] = Studies.list_segments(study.id, status: "proposed")

      view |> form("#prune-form") |> render_submit(%{"keep" => [to_string(a.id)]})
      await_state(study.id, "await_data")

      html = render(view)
      assert html =~ "Scorecard"
      assert html =~ "Run the experiments"
      assert html =~ "still waiting in"

      [exp] = Experiments.list(study.id)
      artifact = Enum.find(Artifacts.list(study.id), &(&1.experiment_id == exp.id))
      {:ok, _, _} = Atlas.Approvals.decide(artifact.id, "approved", nil)

      {:ok, view, _} = live(conn, ~p"/studies/#{study.id}")
      csv = survey_csv(30, 5, 5)

      upload =
        file_input(view, "#upload-form", :result, [
          %{name: "survey.csv", content: csv, type: "text/csv"}
        ])

      render_upload(upload, "survey.csv")

      html =
        view
        |> form("#upload-form", %{experiment_id: exp.id, kind: "survey_csv"})
        |> render_submit()

      assert html =~ "Result uploaded"
      assert [_] = Experiments.list_results(exp.id)

      view |> element("button", "Data collection is done") |> render_click()
      await_state(study.id, "verdict")

      html = render(view)
      assert html =~ "Verdict:"
      assert html =~ "Start loop 2"

      route = Atlas.Scoring.route(Studies.get_study!(study.id).next_move)
      view |> element("button[phx-value-route='#{route}']", "Start loop 2") |> render_click()
      assert Studies.get_study!(study.id).loop_number == 2
    end

    test "shows failures with a retry button", %{conn: conn} do
      Settings.engage_kill_switch()

      {:ok, study} =
        Atlas.Study.start(%{name: "X", description: "A product description.", adapter: "mock"})

      await_state(study.id, "failed")

      {:ok, view, html} = live(conn, ~p"/studies/#{study.id}")
      assert html =~ "Kill switch is on"
      assert html =~ "Kill switch on"

      Settings.release_kill_switch()
      view |> element("button", "Retry") |> render_click()
      await_state(study.id, "hypothesize")
    end

    test "updates the budget", %{conn: conn} do
      study = study_fixture()
      {:ok, view, _} = live(conn, ~p"/studies/#{study.id}")
      view |> form("form[phx-submit=set_budget]", %{budget: "321"}) |> render_submit()
      assert Studies.get_study!(study.id).budget == 321
    end
  end

  describe "evidence ledger" do
    test "lists and filters observations", %{conn: conn} do
      study = study_fixture()
      seg = segment_fixture(study)
      observation_fixture(study, %{segment_id: seg.id, value_text: "segment pain"})

      observation_fixture(study, %{
        evidence_type: "experimental",
        value_text: "study-wide result",
        source_url: nil
      })

      {:ok, view, html} = live(conn, ~p"/studies/#{study.id}/evidence")
      assert html =~ "segment pain"
      assert html =~ "study-wide result"

      html =
        view
        |> element("#filters")
        |> render_change(%{"segment" => to_string(seg.id), "type" => ""})

      assert html =~ "segment pain"
      refute html =~ "study-wide result"

      {:ok, _view, html} = live(conn, ~p"/studies/#{study.id}/evidence?type=experimental")
      refute html =~ "segment pain"
    end
  end

  describe "approvals" do
    test "approves and rejects one at a time; rejection needs a reason", %{conn: conn} do
      study = study_fixture()
      exp = experiment_fixture(study)

      {:ok, survey} =
        Artifacts.create(%{
          study_id: study.id,
          kind: "survey",
          experiment_id: exp.id,
          body: %{"title" => "Pain survey"}
        })

      {:ok, pos} =
        Artifacts.create(%{
          study_id: study.id,
          kind: "positioning",
          body: %{"best_fit_customer" => "Designers"}
        })

      {:ok, view, html} = live(conn, ~p"/approvals")
      assert html =~ "2 waiting"
      assert html =~ "Pain survey"
      assert html =~ "locks this experiment"

      view |> form("#decision", %{note: ""}) |> render_submit(%{"decision" => "approved"})
      assert Artifacts.get!(survey.id).status == "approved"
      assert Experiments.get!(exp.id).status == "locked"

      html = render(view)
      assert html =~ "Designers"

      html = view |> form("#decision", %{note: ""}) |> render_submit(%{"decision" => "rejected"})
      assert html =~ "Say why you are rejecting it"
      assert Artifacts.get!(pos.id).status == "pending_approval"

      view
      |> form("#decision", %{note: "Too generic"})
      |> render_submit(%{"decision" => "rejected"})

      assert Artifacts.get!(pos.id).status == "rejected"
      assert render(view) =~ "The queue is empty"
    end
  end

  describe "skills editor" do
    test "shows skills and validates edits", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/skills?name=survey_design")
      assert html =~ "Survey"
      assert html =~ "experiment_designer"

      html = view |> form("#skill-editor", %{content: "not a skill"}) |> render_submit()
      assert html =~ "frontmatter"

      {:ok, skill} = Atlas.Skills.Library.get("survey_design")
      original = File.read!(skill.path)

      on_exit(fn ->
        File.write!(skill.path, original)
        Atlas.Skills.Library.reload()
      end)

      html =
        view
        |> form("#skill-editor", %{content: String.replace(original, "version: 1", "version: 3")})
        |> render_submit()

      assert html =~ "Saved"
      assert {:ok, %{version: 3}} = Atlas.Skills.Library.get("survey_design")
    end
  end

  describe "usage" do
    test "shows usage, checks backends and toggles the kill switch", %{conn: conn} do
      study = study_fixture()

      Atlas.Usage.record(%{
        study_id: study.id,
        agent: "intake",
        adapter: "mock",
        duration_ms: 12,
        outcome: "ok"
      })

      {:ok, view, html} = live(conn, ~p"/usage")
      assert html =~ "intake"
      assert html =~ "LedgerLite"

      html = view |> element("button", "Check now") |> render_click()
      assert html =~ "built in"

      view |> element("button", "Engage kill switch") |> render_click()
      assert Settings.kill_switch?()
      assert render(view) =~ "Release kill switch"

      view |> element("button", "Release kill switch") |> render_click()
      refute Settings.kill_switch?()
    end
  end

  describe "export" do
    test "only approved approval-kind documents leave", %{conn: conn} do
      study = study_fixture()

      {:ok, survey} =
        Artifacts.create(%{
          study_id: study.id,
          kind: "survey",
          body: %{"questions" => [%{"text" => "When did you last file?"}]}
        })

      conn1 = get(conn, ~p"/artifacts/#{survey.id}/export")
      assert response(conn1, 403) =~ "not been approved"

      {:ok, _, _} = Atlas.Approvals.decide(survey.id, "approved", nil)
      conn2 = get(conn, ~p"/artifacts/#{survey.id}/export")
      body = response(conn2, 200)
      assert body =~ "# Survey"
      assert body =~ "When did you last file?"
      assert get_resp_header(conn2, "content-type") |> hd() =~ "text/markdown"
    end
  end
end
