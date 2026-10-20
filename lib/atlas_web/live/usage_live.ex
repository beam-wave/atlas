defmodule AtlasWeb.UsageLive do
  @moduledoc "Model calls per agent and per study against budget; backend health; kill switch."
  use AtlasWeb, :live_view

  import AtlasWeb.UI

  alias Atlas.{LLM, Settings, Usage}
  alias Atlas.LLM.RateLimiter

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Usage.subscribe()
    {:ok, socket |> assign(page_title: "Usage", doctor: nil) |> load()}
  end

  defp load(socket) do
    assign(socket,
      by_agent: Usage.by_agent(),
      by_study: Usage.by_study(),
      by_adapter: Usage.by_adapter(),
      recent: Usage.recent(15),
      limiter: RateLimiter.status(),
      default_adapter: LLM.resolve_adapter()
    )
  end

  @impl true
  def handle_event("kill_switch", %{"on" => on}, socket) do
    if on == "true", do: Settings.engage_kill_switch(), else: Settings.release_kill_switch()

    msg =
      if on == "true",
        do: "Kill switch on. Every agent call is refused until you release it.",
        else: "Kill switch released. Retry or resume halted studies from their pages."

    {:noreply, put_flash(socket, :info, msg)}
  end

  def handle_event("doctor", _, socket) do
    {:noreply, assign(socket, doctor: LLM.doctor())}
  end

  @impl true
  def handle_info({:llm_call, _}, socket), do: {:noreply, load(socket)}
  def handle_info(_, socket), do: {:noreply, socket}

  defp money(n) when is_number(n) and n > 0,
    do: "$" <> :erlang.float_to_binary(n * 1.0, decimals: 2)

  defp money(_), do: "—"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      active={:usage}
      pending_count={@pending_count}
      kill_switch={@kill_switch}
    >
      <.header>
        Usage
        <:subtitle>Every model call, against each study's budget.</:subtitle>
        <:actions>
          <button
            :if={!@kill_switch}
            phx-click="kill_switch"
            phx-value-on="true"
            class="btn btn-error btn-sm"
            data-confirm="Halt every agent now?"
          >
            <.icon name="hero-stop-circle" class="size-4" /> Engage kill switch
          </button>
          <button :if={@kill_switch} phx-click="kill_switch" phx-value-on="false" class="btn btn-sm">
            Release kill switch
          </button>
        </:actions>
      </.header>

      <div class="stats stats-vertical sm:stats-horizontal border border-base-300 w-full my-6">
        <div class="stat">
          <div class="stat-title">Running now</div>
          <div class="stat-value text-2xl tabular-nums">{@limiter.running} / {@limiter.max}</div>
          <div class="stat-desc">{@limiter.queued} queued</div>
        </div>
        <div class="stat">
          <div class="stat-title">Total calls</div>
          <div class="stat-value text-2xl tabular-nums">
            {Enum.sum(Enum.map(@by_agent, & &1.calls))}
          </div>
          <div class="stat-desc">{Enum.sum(Enum.map(@by_agent, & &1.errors))} failed</div>
        </div>
        <div class="stat">
          <div class="stat-title">Default backend</div>
          <div class="stat-value text-2xl">{@default_adapter}</div>
          <div class="stat-desc">change it on the Studies page</div>
        </div>
      </div>

      <div class="grid lg:grid-cols-2 gap-6">
        <section>
          <h2 class="font-semibold mb-2">By study</h2>
          <table class="table table-sm" id="usage-by-study">
            <thead>
              <tr>
                <th>Product</th>
                <th>Budget</th>
                <th class="text-right">Cost</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={s <- @by_study}>
                <td><.link navigate={~p"/studies/#{s.study_id}"} class="link">{s.product}</.link></td>
                <td><.budget_meter used={s.calls_used} budget={s.budget} /></td>
                <td class="text-right tabular-nums">{money(s.cost_usd)}</td>
              </tr>
            </tbody>
          </table>
        </section>

        <section>
          <h2 class="font-semibold mb-2">By agent</h2>
          <table class="table table-sm" id="usage-by-agent">
            <thead>
              <tr>
                <th>Agent</th>
                <th class="text-right">Calls</th>
                <th class="text-right">Errors</th>
                <th class="text-right">Tokens in/out</th>
                <th class="text-right">Avg</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={a <- @by_agent}>
                <td class="font-mono text-xs">{a.agent}</td>
                <td class="text-right tabular-nums">{a.calls}</td>
                <td class="text-right tabular-nums">{a.errors}</td>
                <td class="text-right tabular-nums text-xs">{a.tokens_in} / {a.tokens_out}</td>
                <td class="text-right tabular-nums text-xs">
                  {if a.avg_ms, do: "#{round(a.avg_ms / 100) / 10}s", else: "—"}
                </td>
              </tr>
            </tbody>
          </table>
        </section>
      </div>

      <section class="mt-8 space-y-3">
        <div class="flex items-center gap-3">
          <h2 class="font-semibold">Model backends</h2>
          <button phx-click="doctor" class="btn btn-ghost btn-xs" phx-disable-with="Checking…">
            Check now
          </button>
        </div>
        <p class="text-sm text-base-content/60">
          Subscription CLIs bill your own plan: install one, log in once in a terminal, and Atlas calls it in print mode.
        </p>
        <ul :if={@doctor} id="doctor" class="grid sm:grid-cols-2 gap-2">
          <li
            :for={{name, result} <- @doctor}
            class="rounded-box border border-base-300 p-3 text-sm flex gap-2"
          >
            <.icon
              :if={match?({:ok, _}, result)}
              name="hero-check-circle"
              class="size-5 text-success shrink-0"
            />
            <.icon
              :if={match?({:error, _}, result)}
              name="hero-x-circle"
              class="size-5 text-base-content/40 shrink-0"
            />
            <span>
              <strong>{name}</strong>
              <br /><span class="text-base-content/70">{elem(result, 1)}</span>
            </span>
          </li>
        </ul>
        <table :if={@by_adapter != []} class="table table-sm max-w-md">
          <thead>
            <tr>
              <th>Backend</th>
              <th class="text-right">Calls</th>
              <th class="text-right">Cost</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={a <- @by_adapter}>
              <td>{a.adapter}</td>
              <td class="text-right tabular-nums">{a.calls}</td>
              <td class="text-right tabular-nums">{money(a.cost_usd)}</td>
            </tr>
          </tbody>
        </table>
      </section>

      <section class="mt-8">
        <h2 class="font-semibold mb-2">Recent calls</h2>
        <table class="table table-xs">
          <thead>
            <tr>
              <th>When</th>
              <th>Agent</th>
              <th>Backend</th>
              <th>Outcome</th>
              <th class="text-right">Time</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={c <- @recent}>
              <td><.time_ago at={c.inserted_at} /></td>
              <td class="font-mono">{c.agent}</td>
              <td>{c.adapter}</td>
              <td class={c.outcome == "error" && "text-error"} title={c.error}>{c.outcome}</td>
              <td class="text-right tabular-nums">{c.duration_ms}ms</td>
            </tr>
          </tbody>
        </table>
      </section>
    </Layouts.app>
    """
  end
end
