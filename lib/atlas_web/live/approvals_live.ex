defmodule AtlasWeb.ApprovalsLive do
  @moduledoc """
  The approval queue, one item at a time. Approving an experiment design
  locks its thresholds; a rejection needs a reason, which the Analyst reads.
  """
  use AtlasWeb, :live_view

  import AtlasWeb.UI

  alias Atlas.{Approvals, Artifacts}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Artifacts.subscribe_queue()
    {:ok, socket |> assign(page_title: "Approvals", note: "") |> load()}
  end

  defp load(socket) do
    queue = Artifacts.approval_queue()
    assign(socket, queue: queue, current: List.first(queue))
  end

  @impl true
  def handle_event("decide", %{"decision" => decision} = params, socket) do
    note = params["note"] || ""

    case Approvals.decide(socket.assigns.current.id, decision, note) do
      {:ok, artifact, _} ->
        msg =
          if decision == "approved",
            do: "Approved #{humanize(artifact.kind)}.",
            else: "Rejected #{humanize(artifact.kind)}."

        {:noreply, socket |> put_flash(:info, msg) |> assign(note: "") |> load()}

      {:error, %Ecto.Changeset{}} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Say why you are rejecting it; the reason improves the skills."
         )}

      {:error, :not_pending} ->
        {:noreply, socket |> put_flash(:error, "Someone already decided this one.") |> load()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not record the decision: #{inspect(reason)}")}
    end
  end

  def handle_event("note", %{"note" => note}, socket), do: {:noreply, assign(socket, note: note)}

  @impl true
  def handle_info(:approvals_changed, socket), do: {:noreply, load(socket)}
  def handle_info(_, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      active={:approvals}
      pending_count={@pending_count}
      kill_switch={@kill_switch}
    >
      <.header>
        Approvals
        <:subtitle>
          Nothing is sent, published or locked without a yes here. {length(@queue)} waiting.
        </:subtitle>
      </.header>

      <div
        :if={!@current}
        class="mt-6 rounded-box border border-dashed border-base-300 p-10 text-center text-base-content/60"
      >
        <.icon name="hero-check-circle" class="size-8 text-success" />
        <p class="mt-2">The queue is empty.</p>
      </div>

      <article
        :if={@current}
        id={"approval-#{@current.id}"}
        class="mt-6 grid lg:grid-cols-[1fr_20rem] gap-6"
      >
        <div class="rounded-box border border-base-300 p-5 space-y-4">
          <div class="flex flex-wrap items-center gap-2">
            <h2 class="text-lg font-semibold">{humanize(@current.kind)}</h2>
            <.review_badge verdict={@current.review_verdict} />
            <span class="text-sm text-base-content/60">
              for
              <.link navigate={~p"/studies/#{@current.study_id}"} class="link">
                {@current.study.product.name}
              </.link>
              · loop {@current.loop_number} · by {@current.agent}
            </span>
          </div>
          <div
            :if={
              (@current.review_notes["issues"] || []) != [] or
                (@current.review_notes["gate_notes"] || []) != []
            }
            class="alert alert-warning alert-soft text-sm block"
          >
            <p class="font-semibold">Reviewer notes</p>
            <.body value={
              (@current.review_notes["issues"] || []) ++ (@current.review_notes["gate_notes"] || [])
            } />
          </div>
          <.body value={@current.body} />
        </div>

        <form
          id="decision"
          phx-submit="decide"
          phx-change="note"
          class="rounded-box border border-base-300 p-5 space-y-3 h-fit lg:sticky lg:top-20"
        >
          <label for="note" class="text-sm font-medium">Reason (required to reject)</label>
          <textarea
            id="note"
            name="note"
            rows="4"
            class="textarea w-full"
            placeholder="What should change?"
          >{@note}</textarea>
          <div class="flex gap-2">
            <button name="decision" value="approved" class="btn btn-primary flex-1">Approve</button>
            <button name="decision" value="rejected" class="btn btn-ghost flex-1">Reject</button>
          </div>
          <p
            :if={@current.kind in ["survey", "interview_guide", "smoke_test"]}
            class="text-xs text-base-content/60"
          >
            Approving locks this experiment's success thresholds. They cannot change once results arrive.
          </p>
          <p :if={@current.kind == "skill_edit_proposal"} class="text-xs text-base-content/60">
            Approving appends this text to the skill; agents use it on their next call.
          </p>
        </form>
      </article>

      <ol :if={length(@queue) > 1} class="mt-6 text-sm text-base-content/60 space-y-1">
        <li class="font-semibold">Up next</li>
        <li :for={a <- tl(@queue)}>{humanize(a.kind)} · {a.study.product.name}</li>
      </ol>
    </Layouts.app>
    """
  end
end
