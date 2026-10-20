defmodule AtlasWeb.StudyLive do
  @moduledoc """
  One study: where it is in the lifecycle, what it needs from you right now,
  the scorecard, experiments and the trail of what happened.
  """
  use AtlasWeb, :live_view

  import AtlasWeb.UI

  alias Atlas.{Artifacts, Audit, Evidence, Experiments, Scoring, Studies, Study}
  alias Atlas.Experiments.Result

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    study = Studies.get_study!(id)

    if connected?(socket) do
      Studies.subscribe(study.id)
      Atlas.Study.Supervisor.ensure_started(study.id)
    end

    {:ok,
     socket
     |> assign(page_title: study.product.name, result_kinds: Result.kinds())
     |> allow_upload(:result,
       accept: ~w(.csv .txt .md),
       max_entries: 1,
       max_file_size: 10_000_000
     )
     |> load(study.id)}
  end

  defp load(socket, id) do
    study = Studies.get_study!(id)
    scorecards = Artifacts.list(study.id, kind: "scorecard") |> Enum.reverse()

    busy =
      case Atlas.Study.Coordinator.status(study.id) do
        %{busy: busy} -> busy
        _ -> false
      end

    assign(socket,
      study: study,
      busy: busy,
      proposed: Studies.list_segments(study.id, status: "proposed", loop: study.loop_number),
      active_segments: Atlas.Study.Steps.active_segments(study),
      hypotheses: Studies.list_hypotheses(study.id) |> Map.new(&{&1.segment_id, &1}),
      scorecard: List.first(scorecards),
      history: scorecards,
      experiments: Experiments.list(study.id) |> Enum.reverse(),
      artifacts: Artifacts.list(study.id) |> Enum.reverse(),
      evidence_counts: Evidence.counts_by_type(study.id),
      audit: Audit.list(study.id, limit: 30),
      default_route: study.next_move && Scoring.route(study.next_move)
    )
  end

  ## Human actions

  @impl true
  def handle_event("prune", params, socket) do
    keep = Map.get(params, "keep", [])

    case Study.prune_segments(socket.assigns.study.id, keep) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "Desk research started for #{length(keep)} segment(s).")
         |> load(socket.assigns.study.id)}

      {:error, :nothing_kept} ->
        {:noreply, put_flash(socket, :error, "Keep at least one segment.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, describe(reason))}
    end
  end

  def handle_event("finish_data", _, socket),
    do: act(socket, &Study.finish_data_collection/1, "Ingesting results.")

  def handle_event("retry", _, socket), do: act(socket, &Study.retry/1, "Retrying.")
  def handle_event("wake", _, socket), do: act(socket, &Study.wake/1, "Resuming.")
  def handle_event("close", _, socket), do: act(socket, &Study.close/1, "Study closed.")

  def handle_event("continue", %{"route" => route}, socket) do
    act(
      socket,
      &Study.continue(&1, route),
      "Loop #{socket.assigns.study.loop_number + 1} started."
    )
  end

  def handle_event("refresh_research", _, socket) do
    %{study_id: socket.assigns.study.id} |> Atlas.Workers.Reobserve.new() |> Oban.insert()

    {:noreply,
     put_flash(
       socket,
       :info,
       "Desk research refresh queued; the scorecard updates when it finishes."
     )}
  end

  def handle_event("set_budget", %{"budget" => budget}, socket) do
    case Studies.update_study(socket.assigns.study, %{budget: budget}) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "Budget updated.") |> load(socket.assigns.study.id)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Budget must be a positive number.")}
    end
  end

  def handle_event("validate_upload", _params, socket), do: {:noreply, socket}

  def handle_event("upload", %{"experiment_id" => exp_id, "kind" => kind}, socket) do
    exp = Experiments.get!(exp_id)

    results =
      consume_uploaded_entries(socket, :result, fn %{path: path}, entry ->
        {:ok, Experiments.upload_result(exp, kind, path, filename: entry.client_name)}
      end)

    socket =
      case results do
        [{:ok, _}] -> put_flash(socket, :info, "Result uploaded.")
        [{:error, reason}] -> put_flash(socket, :error, "Upload refused: #{describe(reason)}")
        [] -> put_flash(socket, :error, "Choose a file first.")
      end

    {:noreply, load(socket, socket.assigns.study.id)}
  end

  defp act(socket, fun, ok_message) do
    case fun.(socket.assigns.study.id) do
      :ok -> {:noreply, socket |> put_flash(:info, ok_message) |> load(socket.assigns.study.id)}
      {:error, reason} -> {:noreply, put_flash(socket, :error, describe(reason))}
    end
  end

  defp describe(:busy), do: "Agents are still working on this step."

  defp describe(:no_results_uploaded),
    do: "Upload at least one result to an approved experiment first."

  defp describe(:not_locked),
    do: "Approve the experiment design first; that locks its thresholds."

  defp describe(:closed), do: "This study is closed."

  defp describe({:not_allowed, state, event}),
    do: "Can't #{event} while the study is in #{state_label(state)}."

  defp describe(other), do: inspect(other)

  @impl true
  def handle_info({:study_event, _id, _event}, socket),
    do: {:noreply, load(socket, socket.assigns.study.id)}

  def handle_info(_, socket), do: {:noreply, socket}

  ## Rendering

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      active={:studies}
      pending_count={@pending_count}
      kill_switch={@kill_switch}
    >
      <div class="space-y-8">
        <section class="space-y-4">
          <div class="flex flex-wrap items-start gap-4">
            <div class="flex-1 min-w-64">
              <.link navigate={~p"/"} class="text-sm text-base-content/60 hover:underline">
                ← Studies
              </.link>
              <h1 class="text-2xl font-semibold tracking-tight mt-1">{@study.product.name}</h1>
              <p class="text-base-content/70 max-w-2xl">{@study.product.description}</p>
            </div>
            <div class="flex flex-col items-end gap-2">
              <div class="flex items-center gap-2">
                <.state_badge state={@study.state} />
                <.verdict_badge verdict={@study.verdict} />
              </div>
              <.budget_meter used={@study.calls_used} budget={@study.budget} />
              <span class="text-xs text-base-content/60">
                Loop {@study.loop_number} · model {Atlas.LLM.resolve_adapter(@study.id)}
              </span>
            </div>
          </div>
          <.stepper state={@study.state} failed_state={@study.failed_state} />
        </section>

        <section id="next-step" class="rounded-box border border-base-300 bg-base-200/40 p-5">
          <.next_step
            study={@study}
            busy={@busy}
            proposed={@proposed}
            hypotheses={@hypotheses}
            experiments={@experiments}
            result_kinds={@result_kinds}
            uploads={@uploads}
            default_route={@default_route}
          />
        </section>

        <section :if={@scorecard} id="scorecard" class="space-y-3">
          <div class="flex items-baseline justify-between">
            <h2 class="text-lg font-semibold">
              Scorecard
              <span class="text-sm font-normal text-base-content/60">
                ({@scorecard.body["stage"]}, loop {@scorecard.loop_number})
              </span>
            </h2>
            <div class="flex items-center gap-3 text-sm">
              <.link navigate={~p"/studies/#{@study.id}/evidence"} class="link">
                Evidence ledger ({Enum.sum(Map.values(@evidence_counts))})
              </.link>
              <button
                :if={@study.state not in ["closed", "intake", "hypothesize"]}
                phx-click="refresh_research"
                class="btn btn-ghost btn-xs"
              >
                <.icon name="hero-arrow-path" class="size-3.5" /> Refresh research
              </button>
            </div>
          </div>
          <div class="grid md:grid-cols-2 gap-4">
            <.scorecard :for={card <- @scorecard.body["segments"] || []} card={card} />
          </div>
          <details :if={length(@history) > 1} class="text-sm">
            <summary class="cursor-pointer text-base-content/70">History across loops</summary>
            <table class="table table-sm mt-2">
              <thead>
                <tr>
                  <th>Loop</th>
                  <th>Stage</th>
                  <th>Top segment</th>
                  <th>Composite</th>
                  <th>Verdict</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={h <- @history}>
                  <% top = List.first(h.body["segments"] || []) || %{} %>
                  <td>{h.loop_number}</td>
                  <td>{h.body["stage"]}</td>
                  <td>{top["name"]}</td>
                  <td class="tabular-nums">{format_score(top["composite"])}</td>
                  <td><.verdict_badge verdict={top["verdict"]} /></td>
                </tr>
              </tbody>
            </table>
          </details>
        </section>

        <section :if={@experiments != []} id="experiments" class="space-y-3">
          <h2 class="text-lg font-semibold">Experiments</h2>
          <div class="grid md:grid-cols-2 gap-4">
            <article
              :for={e <- @experiments}
              id={"experiment-#{e.id}"}
              class="rounded-box border border-base-300 p-4 space-y-2"
            >
              <div class="flex items-start justify-between gap-2">
                <h3 class="font-medium">{e.title}</h3>
                <span class="badge badge-sm badge-ghost">{humanize(e.kind)}</span>
              </div>
              <p class="text-xs text-base-content/60">
                {humanize(e.status)}<span :if={e.outcome}> · <strong>{e.outcome}</strong></span>
                <span :if={e.locked_at}> · thresholds locked <.time_ago at={e.locked_at} /></span>
              </p>
              <ul class="text-sm">
                <li :for={c <- e.thresholds["criteria"] || []} class="font-mono text-xs">
                  {c["metric"]} {c["operator"]} {c["value"]}
                </li>
                <li :if={e.thresholds["min_sample"]} class="text-xs text-base-content/60">
                  min sample {e.thresholds["min_sample"]}
                </li>
              </ul>
              <p :if={e.results != []} class="text-xs text-base-content/70">
                {length(e.results)} result file(s): {Enum.map_join(
                  e.results,
                  ", ",
                  &humanize(&1.kind)
                )}
              </p>
              <p :if={e.status == "draft"} class="text-xs text-warning">
                Waiting for approval in the <.link navigate={~p"/approvals"} class="link">queue</.link>.
              </p>
            </article>
          </div>
        </section>

        <section id="artifacts" class="space-y-3">
          <h2 class="text-lg font-semibold">Documents</h2>
          <ul class="divide-y divide-base-300 rounded-box border border-base-300">
            <li :for={a <- @artifacts} class="p-3">
              <details>
                <summary class="flex flex-wrap items-center gap-2 cursor-pointer">
                  <span class="font-medium">{humanize(a.kind)}</span>
                  <span class="text-xs text-base-content/60">loop {a.loop_number} · {a.agent}</span>
                  <.review_badge verdict={a.review_verdict} />
                  <span
                    :if={a.status != "final"}
                    class={[
                      "badge badge-xs",
                      a.status == "approved" && "badge-success",
                      a.status == "rejected" && "badge-error",
                      a.status == "pending_approval" && "badge-warning"
                    ]}
                  >
                    {humanize(a.status)}
                  </span>
                  <a
                    :if={a.status in ["approved", "final"]}
                    href={~p"/artifacts/#{a.id}/export"}
                    class="link text-xs ml-auto"
                  >
                    Export .md
                  </a>
                </summary>
                <div class="mt-3"><.body value={a.body} /></div>
                <div :if={(a.review_notes["issues"] || []) != []} class="mt-3 text-sm">
                  <p class="font-semibold text-xs uppercase text-base-content/60">Skeptic notes</p>
                  <.body value={a.review_notes["issues"]} />
                </div>
              </details>
            </li>
            <li :if={@artifacts == []} class="p-3 text-sm text-base-content/60">Nothing yet.</li>
          </ul>
        </section>

        <section id="audit" class="space-y-2">
          <details>
            <summary class="cursor-pointer text-lg font-semibold">Audit log</summary>
            <ul class="mt-2 text-sm font-mono space-y-1">
              <li :for={e <- @audit} class="flex gap-3">
                <span class="text-base-content/50 w-20 shrink-0">
                  <.time_ago at={e.inserted_at} />
                </span>
                <span class="font-semibold">{e.kind}</span>
                <span class="text-base-content/70 truncate">{Jason.encode!(e.payload)}</span>
              </li>
            </ul>
          </details>
          <form phx-submit="set_budget" class="flex items-center gap-2 text-sm">
            <label for="budget">Model-call budget</label>
            <input
              id="budget"
              name="budget"
              type="number"
              min="1"
              value={@study.budget}
              class="input input-sm w-24"
            />
            <button class="btn btn-sm">Save</button>
          </form>
        </section>
      </div>
    </Layouts.app>
    """
  end

  defp next_step(%{busy: true} = assigns) do
    ~H"""
    <div class="flex items-center gap-3">
      <span class="loading loading-spinner loading-sm text-primary"></span>
      <div>
        <p class="font-medium">Agents are working: {state_label(@study.state)}</p>
        <p class="text-sm text-base-content/60">This page updates by itself.</p>
      </div>
    </div>
    """
  end

  defp next_step(%{study: %{state: "hypothesize"}} = assigns) do
    ~H"""
    <form id="prune-form" phx-submit="prune" class="space-y-4">
      <div>
        <p class="font-medium">Choose which segments to research</p>
        <p class="text-sm text-base-content/60">
          Keep the ones worth testing. Desk research runs only on what you keep.
        </p>
      </div>
      <div class="grid md:grid-cols-2 gap-3">
        <label
          :for={s <- @proposed}
          class="flex gap-3 rounded-box border border-base-300 bg-base-100 p-3 cursor-pointer has-[:checked]:border-primary"
        >
          <input
            type="checkbox"
            name="keep[]"
            value={s.id}
            class="checkbox checkbox-primary checkbox-sm mt-1"
            checked
          />
          <span class="space-y-1">
            <span class="block font-medium">{s.name}</span>
            <span class="block text-sm text-base-content/70">{s.job_to_be_done["functional"]}</span>
            <span :if={@hypotheses[s.id]} class="block text-xs text-base-content/60">
              Hypothesis: {@hypotheses[s.id].statement}
              <em>Falsified if:</em> {@hypotheses[s.id].falsified_if}
            </span>
          </span>
        </label>
      </div>
      <button class="btn btn-primary btn-sm" phx-disable-with="Starting research…">
        Research kept segments
      </button>
    </form>
    """
  end

  defp next_step(%{study: %{state: "await_data"}} = assigns) do
    locked = Enum.filter(assigns.experiments, &(&1.status == "locked"))
    drafts = Enum.count(assigns.experiments, &(&1.status == "draft"))
    assigns = assign(assigns, locked: locked, drafts: drafts)

    ~H"""
    <div class="space-y-4">
      <div>
        <p class="font-medium">Run the experiments, then upload what came back</p>
        <p class="text-sm text-base-content/60">
          Approving a design locks its thresholds. Upload survey CSVs, interview transcripts, analytics or retention exports.
          <span :if={@drafts > 0}>
            {@drafts} design(s) still waiting in <.link navigate={~p"/approvals"} class="link">Approvals</.link>.
          </span>
        </p>
      </div>

      <form
        :if={@locked != []}
        id="upload-form"
        phx-submit="upload"
        phx-change="validate_upload"
        class="flex flex-wrap items-end gap-3"
      >
        <label class="form-control">
          <span class="label-text text-xs">Experiment</span>
          <select name="experiment_id" class="select select-sm">
            <option :for={e <- @locked} value={e.id}>{e.title}</option>
          </select>
        </label>
        <label class="form-control">
          <span class="label-text text-xs">File type</span>
          <select name="kind" class="select select-sm">
            <option :for={k <- @result_kinds} value={k}>{humanize(k)}</option>
          </select>
        </label>
        <.live_file_input upload={@uploads.result} class="file-input file-input-sm" />
        <button class="btn btn-sm">Upload</button>
        <p :for={err <- upload_errors(@uploads.result)} class="text-error text-xs w-full">
          {inspect(err)}
        </p>
      </form>

      <div class="flex gap-2">
        <button
          phx-click="finish_data"
          class="btn btn-primary btn-sm"
          data-confirm="Close data collection and score the results?"
        >
          Data collection is done
        </button>
      </div>
    </div>
    """
  end

  defp next_step(%{study: %{state: "verdict"}} = assigns) do
    ~H"""
    <div class="space-y-3">
      <p class="font-medium">
        Verdict: <.verdict_badge verdict={@study.verdict} /> · next move
        <strong>{humanize(@study.next_move)}</strong>
      </p>
      <p class="text-sm text-base-content/60">
        The next move sends the study to <strong>{if @default_route == "hypothesize", do: "re-segmenting", else: "the next round of experiments"}</strong>.
        You can choose the other path.
      </p>
      <div class="flex flex-wrap gap-2">
        <button phx-click="continue" phx-value-route={@default_route} class="btn btn-primary btn-sm">
          Start loop {@study.loop_number + 1}: {if @default_route == "hypothesize",
            do: "re-segment",
            else: "design next tests"}
        </button>
        <button
          phx-click="continue"
          phx-value-route={
            if @default_route == "hypothesize", do: "design_tests", else: "hypothesize"
          }
          class="btn btn-ghost btn-sm"
        >
          {if @default_route == "hypothesize", do: "Design tests instead", else: "Re-segment instead"}
        </button>
        <button
          phx-click="close"
          class="btn btn-ghost btn-sm"
          data-confirm="Close this study? It stops here."
        >
          Close study
        </button>
      </div>
    </div>
    """
  end

  defp next_step(%{study: %{state: "failed"}} = assigns) do
    ~H"""
    <div class="space-y-3">
      <p class="font-medium text-error">
        <.icon name="hero-exclamation-triangle" class="size-4" /> {state_label(@study.failed_state)} failed
      </p>
      <pre class="text-xs whitespace-pre-wrap bg-base-100 rounded p-3 border border-base-300">{@study.last_error}</pre>
      <button phx-click="retry" class="btn btn-sm btn-primary">
        Retry {state_label(@study.failed_state)}
      </button>
    </div>
    """
  end

  defp next_step(%{study: %{state: "closed"}} = assigns) do
    ~H"""
    <p class="text-base-content/70">
      This study is closed. Its evidence and documents stay available below.
    </p>
    """
  end

  defp next_step(assigns) do
    ~H"""
    <div class="flex items-center justify-between gap-3">
      <p class="text-base-content/70">Queued: {state_label(@study.state)}.</p>
      <button phx-click="wake" class="btn btn-ghost btn-xs">Run now</button>
    </div>
    """
  end
end
