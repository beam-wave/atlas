defmodule AtlasWeb.EvidenceLive do
  @moduledoc "The evidence ledger: every observation with source, type and confidence."
  use AtlasWeb, :live_view

  import AtlasWeb.UI

  alias Atlas.{Evidence, Studies}
  alias Atlas.Evidence.Observation

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    study = Studies.get_study!(id)
    if connected?(socket), do: Studies.subscribe(study.id)

    segments = Studies.list_segments(study.id, status: ["kept", "proposed"])

    {:ok,
     assign(socket,
       page_title: "Evidence · #{study.product.name}",
       study: study,
       segments: segments,
       segment_names: Map.new(Studies.list_segments(study.id), &{&1.id, &1.name})
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = %{"segment" => params["segment"] || "", "type" => params["type"] || ""}
    {:noreply, socket |> assign(filters: filters) |> load()}
  end

  defp load(socket) do
    %{"segment" => seg, "type" => type} = socket.assigns.filters

    opts =
      [evidence_type: blank(type)]
      |> then(fn o ->
        if blank(seg), do: Keyword.put(o, :segment_id, String.to_integer(seg)), else: o
      end)

    assign(socket, observations: Evidence.list(socket.assigns.study.id, opts) |> Enum.reverse())
  end

  defp blank(""), do: nil
  defp blank(v), do: v

  @impl true
  def handle_event("filter", params, socket) do
    query = params |> Map.take(["segment", "type"]) |> Map.reject(fn {_, v} -> v == "" end)
    {:noreply, push_patch(socket, to: ~p"/studies/#{socket.assigns.study.id}/evidence?#{query}")}
  end

  @impl true
  def handle_info({:study_event, _, {:evidence, _}}, socket), do: {:noreply, load(socket)}
  def handle_info(_, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      active={:studies}
      pending_count={@pending_count}
      kill_switch={@kill_switch}
    >
      <.link navigate={~p"/studies/#{@study.id}"} class="text-sm text-base-content/60 hover:underline">
        ← {@study.product.name}
      </.link>
      <.header>
        Evidence ledger
        <:subtitle>Every claim in this study points at one of these rows.</:subtitle>
      </.header>

      <form id="filters" phx-change="filter" class="flex flex-wrap gap-3 my-4">
        <select name="segment" class="select select-sm" aria-label="Segment">
          <option value="">All segments</option>
          <option :for={s <- @segments} value={s.id} selected={to_string(s.id) == @filters["segment"]}>
            {s.name}
          </option>
        </select>
        <select name="type" class="select select-sm" aria-label="Evidence type">
          <option value="">All evidence types</option>
          <option :for={t <- Observation.evidence_types()} value={t} selected={t == @filters["type"]}>
            {t}
          </option>
        </select>
        <span class="text-sm text-base-content/60 self-center">
          {length(@observations)} observations
        </span>
      </form>

      <div class="overflow-x-auto rounded-box border border-base-300">
        <table class="table table-sm" id="ledger">
          <thead>
            <tr>
              <th>Ref</th>
              <th>Signal</th>
              <th>Value</th>
              <th>Type</th>
              <th class="text-right">Conf.</th>
              <th>Segment</th>
              <th>Source</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={o <- @observations} id={"obs-#{o.id}"}>
              <td class="font-mono text-xs">E{o.id}</td>
              <td class="font-mono text-xs">{o.signal_code}</td>
              <td class="max-w-md">
                <span :if={o.value_num} class="tabular-nums font-medium">
                  {format_score(o.value_num)}
                </span>
                <span class="text-sm">{o.value_text}</span>
              </td>
              <td><.evidence_badge type={o.evidence_type} /></td>
              <td class="text-right tabular-nums">{format_score(o.confidence)}</td>
              <td class="text-xs">{@segment_names[o.segment_id] || "study-wide"}</td>
              <td class="text-xs max-w-xs truncate">
                <a
                  :if={o.source_url}
                  href={o.source_url}
                  target="_blank"
                  rel="noopener noreferrer"
                  class="link"
                >
                  {URI.parse(o.source_url).host || o.source_url}
                </a>
                <span :if={!o.source_url} class="text-base-content/60">{o.source_note}</span>
              </td>
            </tr>
            <tr :if={@observations == []}>
              <td colspan="7" class="text-center text-base-content/60 py-6">
                No observations match.
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </Layouts.app>
    """
  end
end
