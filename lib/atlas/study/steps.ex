defmodule Atlas.Study.Steps do
  @moduledoc """
  The work done in each lifecycle state. Every function takes the study and
  a context and returns one of:

    * `{:next, state}` — move on;
    * `:wait` — the state now needs a person;
    * `{:error, reason}`.

  Control flow is decided here, in code. Agents only produce content.
  """
  require Logger

  alias Atlas.Agents.{
    CompetitorAnalyst,
    EvidenceSynthesizer,
    ExperimentDesigner,
    Intake,
    MarketResearcher,
    PMFScorer,
    PositioningWriter,
    Runner,
    SegmentStrategist,
    Skeptic,
    VoCMiner
  }

  alias Atlas.{Artifacts, Evidence, Experiments, Scoring, Studies}
  alias Atlas.Experiments.Evaluator
  alias Atlas.Studies.Study

  @max_alternatives 6

  def run(state, %Study{} = study, ctx) do
    ctx = Map.merge(%{study_id: study.id, run_id: run_id(state, study)}, ctx)

    case state do
      "intake" -> intake(study, ctx)
      "hypothesize" -> hypothesize(study, ctx)
      "desk_research" -> desk_research(study, ctx)
      "desk_score" -> desk_score(study, ctx)
      "design_tests" -> design_tests(study, ctx)
      "await_data" -> :wait
      "ingest_results" -> ingest_results(study, ctx)
      "verdict" -> verdict(study, ctx)
      other -> {:error, {:no_step_for_state, other}}
    end
  end

  defp run_id(state, study),
    do: "#{state}-L#{study.loop_number}-#{System.unique_integer([:positive])}"

  ## 1. Intake

  def intake(study, ctx) do
    if Artifacts.latest(study.id, "brief") do
      {:next, "hypothesize"}
    else
      input = %{product: product_map(study)}

      with {:ok, brief, meta} <- Runner.run_reviewed(Intake, input, ctx, kind: "product brief") do
        save_artifact(study, "brief", Intake, Runner.to_map(brief), meta)
        {:next, "hypothesize"}
      end
    end
  end

  ## 2. Hypothesize (agent proposes, a person prunes)

  def hypothesize(study, ctx) do
    if Studies.list_segments(study.id, status: "proposed", loop: study.loop_number) != [] do
      :wait
    else
      input = %{
        brief: brief(study),
        previous: previous_segments(study),
        direction: direction(study)
      }

      with {:ok, out, meta} <-
             Runner.run_reviewed(SegmentStrategist, input, ctx,
               kind: "customer segments",
               evidence: []
             ) do
        Atlas.Repo.transaction(fn ->
          for seg <- out.segments do
            {:ok, segment} =
              Studies.create_segment(%{
                study_id: study.id,
                name: seg.name,
                criteria: seg.criteria,
                job_to_be_done: seg.job_to_be_done,
                rationale: seg.rationale,
                loop_number: study.loop_number
              })

            {:ok, _} =
              Studies.create_hypothesis(%{
                study_id: study.id,
                segment_id: segment.id,
                statement: seg.hypothesis.statement,
                falsified_if: seg.hypothesis.falsified_if
              })
          end
        end)

        save_artifact(study, "segments", SegmentStrategist, Runner.to_map(out), meta)
        :wait
      end
    end
  end

  defp previous_segments(study) do
    case Artifacts.latest(study.id, "scorecard") do
      nil ->
        []

      scorecard ->
        for s <- scorecard.body["segments"] || [] do
          Map.take(s, ["name", "verdict", "composite", "next_move"])
        end
    end
  end

  defp direction(%{loop_number: 1}), do: nil

  defp direction(study),
    do: study.next_move && "Last verdict: #{study.verdict}; next move: #{study.next_move}"

  ## 3. Desk research (parallel agents)

  def desk_research(study, ctx) do
    segments = active_segments(study)
    brief = brief(study)

    if segments == [] do
      {:error, :no_kept_segments}
    else
      seg_inputs = Enum.map(segments, &segment_map/1)
      by_name = Map.new(segments, &{normalize(&1.name), &1.id})

      jobs =
        for(
          s <- seg_inputs,
          agent <- [MarketResearcher, VoCMiner],
          do: {agent, %{brief: brief, segment: s}, s.id}
        ) ++
          [{:competitors, %{brief: brief, segments: seg_inputs}, nil}]

      results =
        parallel(ctx, jobs, fn
          {:competitors, input, _} -> competitors(input, ctx)
          {agent, input, seg_id} -> {agent, seg_id, Runner.run(agent, input, ctx)}
        end)

      {stored, failures} = store_research(List.flatten(results), study, ctx, by_name)

      if stored == 0 do
        {:error, {:desk_research_failed, failures}}
      else
        review_research(study, ctx, failures)
        {:next, "desk_score"}
      end
    end
  end

  defp competitors(input, ctx) do
    case Runner.run(CompetitorAnalyst, Map.put(input, :mode, "discover"), ctx) do
      {:ok, discovered, _} ->
        alternatives = Enum.take(discovered.alternatives, @max_alternatives)

        analyses =
          parallel(ctx, alternatives, fn alt ->
            alt_input =
              Map.merge(input, %{
                mode: "analyze",
                alternative: Runner.to_map(alt) |> atomize_name()
              })

            {CompetitorAnalyst, nil, Runner.run(CompetitorAnalyst, alt_input, ctx), alt}
          end)

        [{:competitor_map, alternatives, analyses} | analyses]

      error ->
        [{CompetitorAnalyst, nil, error}]
    end
  end

  defp atomize_name(%{"name" => name} = m), do: Map.put(m, :name, name)

  defp store_research(results, study, ctx, by_name) do
    Enum.reduce(results, {0, []}, fn
      {:competitor_map, alternatives, analyses}, acc ->
        body = %{
          "alternatives" =>
            for {alt, i} <- Enum.with_index(alternatives) do
              profile =
                case Enum.at(analyses, i) do
                  {_, _, {:ok, out, _}, _} -> out.profile
                  _ -> nil
                end

              alt |> Runner.to_map() |> Map.put("profile", profile)
            end
        }

        save_artifact(study, "competitor_map", CompetitorAnalyst, body, %{})
        acc

      {agent, seg_id, {:ok, out, _meta}, _alt}, acc ->
        store_drafts(
          out.observations,
          study,
          ctx,
          agent,
          evidence_type(agent),
          seg_id,
          by_name,
          acc
        )

      {agent, seg_id, {:ok, out, _meta}}, acc ->
        store_drafts(
          out.observations,
          study,
          ctx,
          agent,
          evidence_type(agent),
          seg_id,
          by_name,
          acc
        )

      {agent, _seg, {:error, reason}, _alt}, {n, failures} ->
        {n, [%{"agent" => agent.name(), "error" => inspect(reason)} | failures]}

      {agent, _seg, {:error, reason}}, {n, failures} ->
        {n, [%{"agent" => agent.name(), "error" => inspect(reason)} | failures]}

      {:error, reason}, {n, failures} ->
        {n, [%{"agent" => "unknown", "error" => inspect(reason)} | failures]}
    end)
  end

  defp store_drafts(drafts, study, ctx, agent, type, default_segment_id, by_name, {n, failures}) do
    attrs =
      Enum.map(drafts, &draft_attrs(&1, study, ctx, agent, type, default_segment_id, by_name))

    case Evidence.record_many(attrs) do
      {:ok, obs} ->
        {n + length(obs), failures}

      {:error, {i, cs}} ->
        {n,
         [
           %{
             "agent" => agent.name(),
             "error" => "observation #{i}: #{inspect(Runner.format_errors(cs))}"
           }
           | failures
         ]}
    end
  end

  defp draft_attrs(draft, study, ctx, agent, type, default_segment_id, by_name) do
    segment_id =
      case draft.segment && Map.get(by_name, normalize(draft.segment)) do
        nil -> default_segment_id
        id -> id
      end

    %{
      study_id: study.id,
      segment_id: segment_id,
      signal_code: draft.signal_code,
      value_num: draft.value_num,
      value_text: draft.value_text,
      evidence_type: type,
      confidence: draft.confidence,
      source_url: draft.source_url,
      source_note: draft.source_note,
      run_id: ctx.run_id,
      agent: agent.name(),
      loop_number: study.loop_number,
      experiment_id: ctx[:experiment_id]
    }
  end

  defp evidence_type(VoCMiner), do: "voc"
  defp evidence_type(EvidenceSynthesizer), do: "experimental"
  defp evidence_type(_), do: "desk"

  # One Skeptic pass over the whole desk-research step (not per item, to
  # keep the call budget sane). The verdict is recorded on a research artifact.
  defp review_research(study, ctx, failures) do
    observations = Evidence.list(study.id, loop: study.loop_number)
    digest = Evidence.digest(observations)

    input = %{
      kind: "desk research evidence",
      output: %{"observations" => digest},
      evidence: [],
      context: nil
    }

    {verdict, issues} =
      case Runner.run(Skeptic, input, ctx) do
        {:ok, r, _} ->
          {String.downcase(r.verdict), Enum.map(r.issues, &Runner.to_map/1)}

        {:error, reason} ->
          {"pending", [%{"kind" => "other", "detail" => "review failed: #{inspect(reason)}"}]}
      end

    Artifacts.create(%{
      study_id: study.id,
      kind: "research",
      agent: "desk_research",
      loop_number: study.loop_number,
      body: %{
        "observation_count" => length(observations),
        "by_type" => Evidence.counts_by_type(study.id),
        "failures" => failures
      },
      review_verdict: verdict,
      review_notes: %{"issues" => issues}
    })
  end

  ## 4. Desk score

  def desk_score(study, ctx) do
    with {:ok, cards} <- score_segments(study, ctx, "desk") do
      write_positioning(study, ctx, cards)
      {:next, "design_tests"}
    end
  end

  @doc """
  Scores every active segment, ranks them, stores a scorecard artifact and
  updates the study's verdict. Used by desk_score, verdict and re-score jobs.
  """
  def score_segments(study, ctx, stage) do
    segments = active_segments(study)
    brief = brief(study)

    cards =
      parallel(ctx, segments, fn seg ->
        observations = Evidence.list(study.id, segment_id: seg.id, include_study_wide: true)
        digest = Evidence.digest(observations)
        ids = MapSet.new(observations, & &1.id)

        input = %{
          brief: brief,
          segment: segment_map(seg),
          evidence: digest,
          results: experiment_results(study, seg)
        }

        case Runner.run_reviewed(PMFScorer, input, ctx,
               kind: "PMF scorecard",
               evidence_ids: ids,
               evidence: digest
             ) do
          {:ok, out, meta} ->
            out_map = Runner.to_map(out)
            card = Scoring.score_segment(out_map["ratings"], observations)

            {:ok,
             Map.merge(card, %{
               "segment_id" => seg.id,
               "name" => seg.name,
               "summary" => out.summary,
               "next_experiment" => out.next_experiment,
               "model_next_move" => out.next_move_suggestion,
               "claims" => out_map["claims"],
               "review_verdict" => meta.review_verdict
             }), meta}

          {:error, reason} ->
            {:error, seg.name, reason}
        end
      end)

    ok = for {:ok, card, _} <- cards, do: card

    errors =
      for {:error, name, reason} <- cards, do: %{"segment" => name, "error" => inspect(reason)}

    if ok == [] do
      {:error, {:scoring_failed, errors}}
    else
      ranked = Enum.sort_by(ok, &(-(&1["composite"] || -1)))
      Studies.rank_segments(Enum.map(ranked, & &1["segment_id"]))
      [top | _] = ranked

      skill_versions =
        cards
        |> Enum.find_value(%{}, fn
          {:ok, _, m} -> m.skill_versions
          _ -> nil
        end)

      save_artifact(
        study,
        "scorecard",
        PMFScorer,
        %{
          "stage" => stage,
          "segments" => ranked,
          "errors" => errors,
          "top_segment" => top["name"]
        },
        %{
          skill_versions: skill_versions,
          review_verdict:
            if(Enum.all?(ranked, &(&1["review_verdict"] == "pass")), do: "pass", else: "revise")
        }
      )

      {:ok, _} =
        Studies.update_study(Studies.get_study!(study.id), %{
          verdict: top["verdict"],
          next_move: top["next_move"]
        })

      {:ok, ranked}
    end
  end

  defp experiment_results(study, segment) do
    for e <- Experiments.list(study.id, status: "completed"), e.segment_id == segment.id do
      %{
        "title" => e.title,
        "kind" => e.kind,
        "outcome" => e.outcome,
        "thresholds" => e.thresholds,
        "metrics" =>
          e.results
          |> Enum.map(& &1.summary["metrics"])
          |> Enum.reduce(%{}, &Map.merge(&2, &1 || %{}))
      }
    end
  end

  defp write_positioning(study, ctx, cards) do
    top = Enum.take(cards, top_n(study))
    brief = brief(study)

    parallel(ctx, top, fn card ->
      seg = Studies.get_segment!(card["segment_id"])
      observations = Evidence.list(study.id, segment_id: seg.id, include_study_wide: true)
      digest = Evidence.digest(observations)
      input = %{brief: brief, segment: segment_map(seg), scorecard: card, evidence: digest}

      case Runner.run_reviewed(PositioningWriter, input, ctx,
             kind: "positioning",
             evidence_ids: MapSet.new(observations, & &1.id),
             evidence: digest,
             banned_phrases: true
           ) do
        {:ok, out, meta} ->
          save_artifact(study, "positioning", PositioningWriter, Runner.to_map(out), meta,
            segment_id: seg.id
          )

        {:error, reason} ->
          Logger.warning("positioning for #{seg.name} failed: #{inspect(reason)}")
      end
    end)
  end

  defp top_n(%{next_move: "narrow"}), do: 1
  defp top_n(_), do: Application.get_env(:atlas, :top_segments, 2)

  ## 5. Design tests

  def design_tests(study, ctx) do
    segments =
      active_segments(study) |> Enum.sort_by(&(&1.rank || 999)) |> Enum.take(top_n(study))

    brief = brief(study)

    # Falsified hypotheses are done; supported ones get the next, harder test
    # (the designer sees what already ran).
    jobs =
      for seg <- segments,
          h <- Studies.list_hypotheses(study.id, [seg.id]),
          h.status != "falsified",
          do: {seg, h}

    if jobs == [] do
      {:error, :no_open_hypotheses}
    else
      results =
        parallel(ctx, jobs, fn {seg, h} ->
          observations = Evidence.list(study.id, segment_id: seg.id, include_study_wide: true)

          input = %{
            brief: brief,
            segment: segment_map(seg),
            hypothesis: %{statement: h.statement, falsified_if: h.falsified_if},
            evidence: Evidence.digest(observations),
            previous: previous_experiments(study, seg)
          }

          with {:ok, out, meta} <-
                 Runner.run_reviewed(ExperimentDesigner, input, ctx, kind: "experiment design"),
               {:ok, exp} <-
                 Experiments.create(%{
                   study_id: study.id,
                   hypothesis_id: h.id,
                   segment_id: seg.id,
                   kind: out.kind,
                   title: out.title,
                   design:
                     Map.merge(out.design, %{
                       "rationale" => out.rationale,
                       "cost_estimate" => out.cost_estimate
                     }),
                   thresholds: out.thresholds,
                   loop_number: study.loop_number
                 }) do
            save_artifact(
              study,
              artifact_kind(out.kind),
              ExperimentDesigner,
              Runner.to_map(out),
              meta,
              segment_id: seg.id,
              experiment_id: exp.id
            )
          end
        end)

      if Enum.any?(results, &match?({:ok, _}, &1)) do
        {:next, "await_data"}
      else
        {:error, {:design_failed, Enum.map(results, &inspect/1)}}
      end
    end
  end

  defp artifact_kind("survey"), do: "survey"
  defp artifact_kind("interview"), do: "interview_guide"
  defp artifact_kind("smoke_test"), do: "smoke_test"

  defp previous_experiments(study, seg) do
    for e <- Experiments.list(study.id), e.segment_id == seg.id do
      %{"title" => e.title, "kind" => e.kind, "status" => e.status, "outcome" => e.outcome}
    end
  end

  ## 6. Await data — people run the tests. See `ready_for_ingest/1`.

  @doc "Data collection can close once a locked experiment has at least one result."
  def ready_for_ingest(study) do
    if Enum.any?(Experiments.list(study.id, status: "locked"), &(&1.results != [])),
      do: :ok,
      else: {:error, :no_results_uploaded}
  end

  ## 7. Ingest results

  def ingest_results(study, ctx) do
    experiments = Experiments.list(study.id, status: "locked") |> Enum.filter(&(&1.results != []))

    outcomes =
      for exp <- experiments do
        ctx = Map.put(ctx, :experiment_id, exp.id)
        metrics = ingest_experiment(study, exp, ctx)
        {outcome, checks} = Evaluator.evaluate(exp.thresholds, metrics)
        {:ok, _} = Experiments.complete(exp, outcome)
        record_metrics(study, exp, metrics, outcome, ctx)
        update_hypothesis(exp, outcome)

        Atlas.Audit.log(study.id, "experiment_evaluated", %{
          experiment_id: exp.id,
          outcome: outcome,
          checks: checks,
          metrics: metrics
        })

        outcome
      end

    if outcomes == [], do: {:error, :no_results_uploaded}, else: {:next, "verdict"}
  end

  defp ingest_experiment(study, exp, ctx) do
    brief = brief(study)
    segments = Enum.map(active_segments(study), &segment_map/1)
    by_name = Map.new(active_segments(study), &{normalize(&1.name), &1.id})
    exp_info = %{title: exp.title, kind: exp.kind, segment_id: exp.segment_id}

    {metrics, interviews} =
      Enum.reduce(exp.results, {%{}, []}, fn result, {m, interviews} ->
        m = Map.merge(m, result.summary["metrics"] || %{})

        case result.kind do
          "transcript" ->
            {:ok, text} = Experiments.read_upload(result)

            input = %{
              brief: brief,
              segments: segments,
              experiment: exp_info,
              material_kind: "transcript",
              material: String.slice(text, 0, 60_000)
            }

            case Runner.run(EvidenceSynthesizer, input, ctx) do
              {:ok, out, _} ->
                store_drafts(
                  out.observations,
                  study,
                  ctx,
                  EvidenceSynthesizer,
                  "experimental",
                  exp.segment_id,
                  by_name,
                  {0, []}
                )

                {m, [out.interview | interviews]}

              {:error, reason} ->
                Logger.warning("transcript synthesis failed: #{inspect(reason)}")
                {m, interviews}
            end

          "survey_csv" ->
            open_text = result.summary["open_text"] || []

            if open_text != [] do
              input = %{
                brief: brief,
                segments: segments,
                experiment: exp_info,
                material_kind: "survey open text",
                material: open_text
              }

              with {:ok, out, _} <- Runner.run(EvidenceSynthesizer, input, ctx) do
                store_drafts(
                  out.observations,
                  study,
                  ctx,
                  EvidenceSynthesizer,
                  "experimental",
                  exp.segment_id,
                  by_name,
                  {0, []}
                )
              end
            end

            {m, interviews}

          _ ->
            {m, interviews}
        end
      end)

    metrics
    |> Map.delete("words")
    |> Map.merge(interview_metrics(interviews))
    |> put_sample_size(exp.kind)
  end

  # The sample a threshold's min_sample refers to depends on the kind of test.
  defp put_sample_size(m, "survey"),
    do: Map.put(m, "sample_size", m["sean_ellis_responses"] || m["responses"])

  defp put_sample_size(m, "interview"), do: Map.put(m, "sample_size", m["interview_count"])
  defp put_sample_size(m, "smoke_test"), do: Map.put(m, "sample_size", m["visits"])
  defp put_sample_size(m, _), do: m

  defp interview_metrics([]), do: %{}

  defp interview_metrics(interviews) do
    n = length(interviews)
    pct = fn key -> Float.round(Enum.count(interviews, &(&1[key] == true)) * 100 / n, 1) end

    %{
      "interview_count" => n,
      "interview_pain_confirmed_pct" => pct.("pain_confirmed"),
      "interview_past_spend_pct" => pct.("past_spend"),
      "interview_switching_intent_pct" => pct.("switching_intent")
    }
  end

  @metric_signals %{
    "sean_ellis_very_disappointed_pct" => "sean_ellis_very_disappointed_pct",
    "sean_ellis_responses" => "sean_ellis_responses",
    "vw_too_cheap" => "vw_too_cheap",
    "vw_bargain" => "vw_bargain",
    "vw_expensive" => "vw_expensive",
    "vw_too_expensive" => "vw_too_expensive",
    "visits" => "visits",
    "signups" => "signups",
    "preorders" => "preorder_count",
    "signup_conversion_pct" => "signup_conversion_pct",
    "cost_per_signup" => "signup_cost_per_channel",
    "retention_final_pct" => "retention_pct",
    "retention_flattening" => "retention_flattening",
    "interview_count" => "interview_count",
    "interview_pain_confirmed_pct" => "interview_pain_confirmed",
    "interview_past_spend_pct" => "interview_past_spend",
    "interview_switching_intent_pct" => "switching_intent"
  }

  defp record_metrics(study, exp, metrics, outcome, ctx) do
    sample = metrics["sample_size"]
    min = exp.thresholds["min_sample"]
    confidence = confidence(sample, min)
    note = "Experiment ##{exp.id}: #{exp.title}"

    rows =
      for {metric, code} <- @metric_signals, is_number(metrics[metric]) do
        %{
          signal_code: code,
          value_num: metrics[metric] * 1.0,
          value_text: "#{metric} (n=#{sample || "?"})"
        }
      end

    outcome_row = %{
      signal_code: "experiment_outcome",
      value_num: outcome_value(outcome),
      value_text: "#{exp.title}: #{outcome}"
    }

    (rows ++ [outcome_row])
    |> Enum.map(fn row ->
      Map.merge(row, %{
        study_id: study.id,
        segment_id: exp.segment_id,
        experiment_id: exp.id,
        evidence_type: "experimental",
        confidence: confidence,
        source_note: note,
        run_id: ctx.run_id,
        agent: "ingest",
        loop_number: study.loop_number
      })
    end)
    |> Evidence.record_many()
  end

  defp confidence(sample, min) when is_number(sample) and is_number(min) and min > 0,
    do: Float.round(min(1.0, 0.5 + 0.5 * sample / (2 * min)), 2)

  defp confidence(sample, _) when is_number(sample),
    do: Float.round(min(1.0, 0.4 + sample / 200), 2)

  defp confidence(_, _), do: 0.5

  defp outcome_value("passed"), do: 1.0
  defp outcome_value("failed"), do: 0.0
  defp outcome_value(_), do: 0.5

  defp update_hypothesis(%{hypothesis_id: nil}, _), do: :ok

  defp update_hypothesis(exp, outcome) do
    status = %{"passed" => "supported", "failed" => "falsified"}[outcome] || "open"
    Studies.update_hypothesis(Studies.get_hypothesis!(exp.hypothesis_id), %{status: status})
  end

  ## 8. Verdict

  def verdict(study, ctx) do
    with {:ok, _cards} <- score_segments(study, ctx, "verdict") do
      :wait
    end
  end

  ## Helpers

  @doc """
  The segments currently under study: the kept segments from the most recent
  loop that kept any.
  """
  def active_segments(study) do
    kept = Studies.list_segments(study.id, status: "kept")

    case kept do
      [] ->
        []

      _ ->
        latest = kept |> Enum.map(& &1.loop_number) |> Enum.max()
        Enum.filter(kept, &(&1.loop_number == latest))
    end
  end

  defp product_map(study) do
    Map.take(study.product, [:name, :description, :url, :price])
  end

  defp brief(study) do
    case Artifacts.latest(study.id, "brief") do
      nil -> %{"product" => product_map(study)}
      a -> a.body
    end
  end

  defp segment_map(seg) do
    %{
      id: seg.id,
      name: seg.name,
      criteria: seg.criteria,
      job_to_be_done: seg.job_to_be_done,
      rationale: seg.rationale
    }
  end

  defp normalize(name), do: name |> to_string() |> String.downcase() |> String.trim()

  defp save_artifact(study, kind, agent, body, meta, extra \\ []) do
    {:ok, artifact} =
      Artifacts.create(%{
        study_id: study.id,
        kind: kind,
        agent: agent.name(),
        loop_number: study.loop_number,
        body: body,
        review_verdict: meta[:review_verdict] || "pending",
        review_notes: meta[:review_notes] || %{},
        skill_versions: meta[:skill_versions] || %{},
        segment_id: extra[:segment_id],
        experiment_id: extra[:experiment_id]
      })

    {:ok, artifact}
  end

  # Fan out under the study's Task.Supervisor when there is one (supervised,
  # crash-isolated), inline otherwise. A crashed item becomes {:error, ...}.
  defp parallel(ctx, items, fun) do
    case ctx[:task_sup] do
      nil ->
        Enum.map(items, fn item ->
          try do
            fun.(item)
          rescue
            e -> {:error, {:crashed, Exception.message(e)}}
          end
        end)

      sup ->
        sup
        |> Task.Supervisor.async_stream_nolink(items, fun,
          timeout: :infinity,
          max_concurrency: 16,
          ordered: true
        )
        |> Enum.map(fn
          {:ok, result} -> result
          {:exit, reason} -> {:error, {:crashed, reason}}
        end)
    end
  end
end
