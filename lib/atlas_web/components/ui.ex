defmodule AtlasWeb.UI do
  @moduledoc "Small presentation components shared by the dashboard pages."
  use Phoenix.Component
  import AtlasWeb.CoreComponents, only: [icon: 1]

  @lifecycle [
    {"intake", "Intake"},
    {"hypothesize", "Hypothesize"},
    {"desk_research", "Desk research"},
    {"desk_score", "Desk score"},
    {"design_tests", "Design tests"},
    {"await_data", "Await data"},
    {"ingest_results", "Ingest results"},
    {"verdict", "Verdict"}
  ]

  def lifecycle, do: @lifecycle

  def state_label(state),
    do: (List.keyfind(@lifecycle, state, 0) || {state, humanize(state)}) |> elem(1)

  def humanize(nil), do: "—"
  def humanize(s), do: s |> to_string() |> String.replace("_", " ") |> String.capitalize()

  attr :state, :string, required: true

  def state_badge(assigns) do
    ~H"""
    <span class={["badge badge-sm whitespace-nowrap", state_class(@state)]}>
      {state_label(@state)}
    </span>
    """
  end

  defp state_class(s) when s in ["hypothesize", "await_data", "verdict"], do: "badge-warning"
  defp state_class("failed"), do: "badge-error"
  defp state_class("closed"), do: "badge-ghost"
  defp state_class(_), do: "badge-info badge-soft"

  attr :verdict, :string, default: nil

  def verdict_badge(assigns) do
    ~H"""
    <span :if={@verdict} class={["badge badge-sm whitespace-nowrap", verdict_class(@verdict)]}>
      {verdict_label(@verdict)}
    </span>
    <span :if={!@verdict} class="text-base-content/40 text-sm">—</span>
    """
  end

  def verdict_label("no_signal"), do: "No signal yet"
  def verdict_label("promising"), do: "Promising"
  def verdict_label("approaching_fit"), do: "Approaching fit"
  def verdict_label("fit"), do: "Fit"
  def verdict_label(other), do: humanize(other)

  defp verdict_class("fit"), do: "badge-success"
  defp verdict_class("approaching_fit"), do: "badge-success badge-soft"
  defp verdict_class("promising"), do: "badge-info badge-soft"
  defp verdict_class(_), do: "badge-ghost"

  attr :type, :string, required: true

  def evidence_badge(assigns) do
    ~H"""
    <span class={[
      "badge badge-xs font-mono",
      @type == "experimental" && "badge-success",
      @type == "voc" && "badge-info badge-soft",
      @type == "desk" && "badge-ghost"
    ]}>
      {@type}
    </span>
    """
  end

  attr :verdict, :string, required: true

  def review_badge(assigns) do
    ~H"""
    <span class={[
      "badge badge-xs",
      @verdict == "pass" && "badge-success badge-soft",
      @verdict == "revise" && "badge-warning",
      @verdict == "pending" && "badge-ghost"
    ]}>
      Skeptic: {@verdict}
    </span>
    """
  end

  @doc "The eight-state lifecycle with the current state highlighted."
  attr :state, :string, required: true
  attr :failed_state, :string, default: nil

  def stepper(assigns) do
    current = if assigns.state == "failed", do: assigns.failed_state, else: assigns.state
    index = Enum.find_index(@lifecycle, &(elem(&1, 0) == current)) || length(@lifecycle)
    assigns = assign(assigns, index: index, current: current)

    ~H"""
    <ol class="grid grid-cols-4 lg:grid-cols-8 gap-1 text-xs" aria-label="Study lifecycle">
      <li
        :for={{{key, label}, i} <- Enum.with_index(lifecycle())}
        class={[
          "rounded-md px-2 py-1.5 border transition-colors",
          i < @index && "border-base-300 text-base-content/60",
          key == @current && @state != "failed" &&
            "border-primary bg-primary/10 text-primary font-semibold",
          key == @current && @state == "failed" &&
            "border-error bg-error/10 text-error font-semibold",
          i > @index && "border-dashed border-base-300 text-base-content/40"
        ]}
        aria-current={key == @current && "step"}
      >
        <span class="tabular-nums">{i + 1}</span> {label}
        <.icon :if={key in ["hypothesize", "await_data"]} name="hero-user" class="size-3 ml-0.5" />
      </li>
    </ol>
    """
  end

  @doc "Calls used against budget."
  attr :used, :integer, required: true
  attr :budget, :integer, required: true

  def budget_meter(assigns) do
    pct = if assigns.budget > 0, do: min(100, round(assigns.used * 100 / assigns.budget)), else: 0
    assigns = assign(assigns, pct: pct)

    ~H"""
    <div class="flex items-center gap-2 text-xs" title="Model calls used / budget">
      <progress
        class={["progress w-24", @pct >= 90 && "progress-error", @pct < 90 && "progress-primary"]}
        value={@pct}
        max="100"
      >
      </progress>
      <span class="tabular-nums text-base-content/70">{@used} / {@budget} calls</span>
    </div>
    """
  end

  @doc "One segment's scorecard ratings."
  attr :card, :map, required: true

  def scorecard(assigns) do
    ~H"""
    <div class="rounded-box border border-base-300 p-4 space-y-3">
      <div class="flex flex-wrap items-baseline justify-between gap-2">
        <h3 class="font-semibold">{@card["name"]}</h3>
        <div class="flex items-center gap-2">
          <span class="text-2xl font-semibold tabular-nums">{format_score(@card["composite"])}</span>
          <.verdict_badge verdict={@card["verdict"]} />
        </div>
      </div>
      <p :if={@card["guard_note"]} class="text-xs text-warning">
        <.icon name="hero-shield-exclamation" class="size-3.5" /> {@card["guard_note"]}
      </p>
      <table class="table table-xs">
        <thead>
          <tr>
            <th>Dimension</th>
            <th class="text-right">Score</th>
            <th>Evidence</th>
            <th>Cites</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={r <- @card["ratings"] || []}>
            <td>{humanize(r["dimension"])}</td>
            <td class="text-right tabular-nums">{format_score(r["score"])}/5</td>
            <td><.evidence_badge type={r["evidence_type"]} /></td>
            <td class="font-mono text-xs text-base-content/60">
              {Enum.join(r["evidence_ids"] || [], " ")}
            </td>
          </tr>
          <tr :if={(@card["ratings"] || []) == []}>
            <td colspan="4" class="text-base-content/50">No dimension has evidence yet.</td>
          </tr>
        </tbody>
      </table>
      <dl class="grid grid-cols-[auto_1fr] gap-x-3 gap-y-1 text-sm">
        <dt class="text-base-content/60">Next move</dt>
        <dd class="font-medium">{humanize(@card["next_move"])}</dd>
        <dt class="text-base-content/60">Next experiment</dt>
        <dd>{@card["next_experiment"]}</dd>
        <dt :if={@card["summary"]} class="text-base-content/60">Summary</dt>
        <dd :if={@card["summary"]}>{@card["summary"]}</dd>
      </dl>
    </div>
    """
  end

  def format_score(nil), do: "—"

  def format_score(n) when is_float(n),
    do: :erlang.float_to_binary(n, decimals: 1) |> String.trim_trailing(".0")

  def format_score(n), do: to_string(n)

  @doc "Renders an artifact body (any JSON-like map) as readable nested content."
  attr :value, :any, required: true
  attr :depth, :integer, default: 0

  def body(%{value: value} = assigns) when is_map(value) and map_size(value) > 0 do
    ~H"""
    <dl class={["space-y-2", @depth > 0 && "pl-3 border-l border-base-300"]}>
      <div :for={{k, v} <- Enum.sort_by(@value, &elem(&1, 0))}>
        <dt class="text-xs font-semibold uppercase tracking-wide text-base-content/60">
          {humanize(k)}
        </dt>
        <dd class="text-sm"><.body value={v} depth={@depth + 1} /></dd>
      </div>
    </dl>
    """
  end

  def body(%{value: value} = assigns) when is_list(value) and value != [] do
    ~H"""
    <ul class="list-disc pl-5 space-y-1">
      <li :for={v <- @value}><.body value={v} depth={@depth + 1} /></li>
    </ul>
    """
  end

  def body(%{value: value} = assigns) when value in [nil, "", [], %{}] do
    ~H"""
    <span class="text-base-content/40">—</span>
    """
  end

  def body(assigns) do
    ~H"""
    <span class="whitespace-pre-wrap">{to_string(@value)}</span>
    """
  end

  attr :at, :any, required: true

  def time_ago(assigns) do
    ~H"""
    <time datetime={@at && DateTime.to_iso8601(@at)} title={@at && DateTime.to_iso8601(@at)}>
      {ago(@at)}
    </time>
    """
  end

  def ago(nil), do: "—"

  def ago(%DateTime{} = at) do
    s = DateTime.diff(DateTime.utc_now(), at)

    cond do
      s < 60 -> "just now"
      s < 3600 -> "#{div(s, 60)}m ago"
      s < 86_400 -> "#{div(s, 3600)}h ago"
      true -> "#{div(s, 86_400)}d ago"
    end
  end
end
