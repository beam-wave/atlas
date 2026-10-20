defmodule AtlasWeb.SkillsLive do
  @moduledoc "View and edit the Markdown skills. Changes apply on the next agent call."
  use AtlasWeb, :live_view

  alias Atlas.Skills.Library

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Atlas.PubSub, "skills")
    {:ok, socket |> assign(page_title: "Skills", errors: []) |> load()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    name = params["name"] || (List.first(socket.assigns.skills) || %{name: nil}).name
    {:noreply, select(socket, name)}
  end

  defp load(socket) do
    assign(socket,
      skills: Library.all(),
      load_errors: Library.errors(),
      skill_map: Library.skill_map()
    )
  end

  defp select(socket, nil), do: assign(socket, selected: nil, content: "", errors: [])

  defp select(socket, name) do
    case Library.get(name) do
      {:ok, skill} -> assign(socket, selected: skill, content: File.read!(skill.path), errors: [])
      _ -> assign(socket, selected: nil, content: "", errors: [])
    end
  end

  @impl true
  def handle_event("save", %{"content" => content}, socket) do
    case Library.write(socket.assigns.selected.name, content) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "Saved. Agents use it from their next call.")
         |> load()
         |> select(socket.assigns.selected.name)}

      {:error, errors} ->
        {:noreply, assign(socket, content: content, errors: List.wrap(errors))}
    end
  end

  @impl true
  def handle_info({:skill_changed, _}, socket), do: {:noreply, load(socket)}
  def handle_info(_, socket), do: {:noreply, socket}

  defp agents_using(skill_map, name) do
    for {agent, skills} <- skill_map, name in skills, do: agent
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      active={:skills}
      pending_count={@pending_count}
      kill_switch={@kill_switch}
    >
      <.header>
        Skills
        <:subtitle>
          Agents' working knowledge, as Markdown in <code class="text-xs">{Library.dir()}</code>.
          Edit here or in your editor; both apply on the next call.
        </:subtitle>
      </.header>

      <div :if={@load_errors != %{}} class="alert alert-error alert-soft my-4 block text-sm">
        <p class="font-semibold">Skipped invalid files (last good version stays loaded):</p>
        <p :for={{file, errs} <- @load_errors}>{file}: {Enum.join(errs, "; ")}</p>
      </div>

      <div class="grid md:grid-cols-[16rem_1fr] gap-6 mt-6">
        <nav aria-label="Skills" class="space-y-4">
          <div :for={{group, skills} <- Enum.group_by(@skills, & &1.group)}>
            <p class="text-xs font-semibold uppercase tracking-wide text-base-content/50 mb-1">
              {group}
            </p>
            <ul>
              <li :for={s <- skills}>
                <.link
                  patch={~p"/skills?#{[name: s.name]}"}
                  class={[
                    "block rounded px-2 py-1 text-sm",
                    @selected && @selected.name == s.name && "bg-base-200 font-medium",
                    !(@selected && @selected.name == s.name) && "hover:bg-base-200/60"
                  ]}
                >
                  {s.title} <span class="text-xs text-base-content/50">v{s.version}</span>
                </.link>
              </li>
            </ul>
          </div>
        </nav>

        <section :if={@selected} class="space-y-3">
          <div>
            <h2 class="text-lg font-semibold">{@selected.title}</h2>
            <p class="text-sm text-base-content/70">{@selected.description}</p>
            <p class="text-xs text-base-content/60 mt-1">
              Used by: {Enum.join(agents_using(@skill_map, @selected.name), ", ")
              |> then(&if(&1 == "", do: "no agent", else: &1))} · hash <code>{@selected.hash}</code>
            </p>
          </div>
          <form id="skill-editor" phx-submit="save" class="space-y-2">
            <textarea
              name="content"
              rows="28"
              class="textarea w-full font-mono text-xs leading-relaxed"
              spellcheck="false"
            >{@content}</textarea>
            <ul :if={@errors != []} class="text-error text-sm">
              <li :for={e <- @errors}>{e}</li>
            </ul>
            <button class="btn btn-primary btn-sm" phx-disable-with="Saving…">Save skill</button>
          </form>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
