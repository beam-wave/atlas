defmodule AtlasWeb.StudiesLive do
  @moduledoc "Studies list and the new-study form."
  use AtlasWeb, :live_view

  import AtlasWeb.UI

  alias Atlas.{LLM, Settings, Studies}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Studies.subscribe()

    {:ok,
     socket
     |> assign(
       page_title: "Studies",
       adapters: LLM.adapter_names(),
       default_adapter: LLM.resolve_adapter()
     )
     |> assign(form: new_form())
     |> load()}
  end

  defp new_form(params \\ %{}) do
    defaults = %{
      "name" => "",
      "description" => "",
      "url" => "",
      "price" => "",
      "budget" => "150",
      "adapter" => ""
    }

    to_form(Map.merge(defaults, params), as: :study)
  end

  defp load(socket), do: assign(socket, studies: Studies.list_studies())

  @impl true
  def handle_event("validate", %{"study" => params}, socket) do
    {:noreply, assign(socket, form: new_form(params))}
  end

  def handle_event("create", %{"study" => params}, socket) do
    attrs =
      params
      |> Map.update("adapter", nil, &blank_to_nil/1)
      |> Map.update("url", nil, &blank_to_nil/1)

    case Atlas.Study.start(attrs) do
      {:ok, study} ->
        {:noreply,
         socket
         |> put_flash(:info, "Study started.")
         |> push_navigate(to: ~p"/studies/#{study.id}")}

      {:error, %Ecto.Changeset{} = cs} ->
        {:noreply, assign(socket, form: to_form(%{cs | action: :insert}, as: :study))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not start the study: #{inspect(reason)}")}
    end
  end

  def handle_event("set_default_adapter", %{"adapter" => adapter}, socket) do
    Settings.put("default_adapter", blank_to_nil(adapter))
    {:noreply, assign(socket, default_adapter: LLM.resolve_adapter())}
  end

  @impl true
  def handle_info({:study_event, _id, _event}, socket), do: {:noreply, load(socket)}
  def handle_info(_, socket), do: {:noreply, socket}

  defp blank_to_nil(v) when v in [nil, ""], do: nil
  defp blank_to_nil(v), do: v

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      active={:studies}
      pending_count={@pending_count}
      kill_switch={@kill_switch}
    >
      <div class="grid lg:grid-cols-[1fr_22rem] gap-8">
        <section>
          <.header>
            Studies
            <:subtitle>
              Each study scores one product's fit, segment by segment, from evidence.
            </:subtitle>
          </.header>

          <div
            :if={@studies == []}
            class="mt-6 rounded-box border border-dashed border-base-300 p-8 text-center text-base-content/60"
          >
            No studies yet. Describe a product on the right to start one.
          </div>

          <ul
            :if={@studies != []}
            id="studies"
            class="mt-6 divide-y divide-base-300 rounded-box border border-base-300"
          >
            <li :for={s <- @studies} id={"study-#{s.id}"}>
              <.link
                navigate={~p"/studies/#{s.id}"}
                class="flex flex-wrap items-center gap-3 p-4 hover:bg-base-200/50 transition-colors"
              >
                <div class="flex-1 min-w-48">
                  <p class="font-medium">{s.product.name}</p>
                  <p class="text-sm text-base-content/60 line-clamp-1">{s.product.description}</p>
                </div>
                <.state_badge state={s.state} />
                <.verdict_badge verdict={s.verdict} />
                <span class="text-xs text-base-content/60 w-16">Loop {s.loop_number}</span>
                <span class="text-xs text-base-content/50 w-20 text-right">
                  <.time_ago at={s.updated_at} />
                </span>
              </.link>
            </li>
          </ul>
        </section>

        <aside class="space-y-6">
          <div class="rounded-box border border-base-300 p-5">
            <h2 class="font-semibold mb-1">New study</h2>
            <p class="text-sm text-base-content/60 mb-4">
              Agents draft segments; you prune them before research starts.
            </p>
            <.form
              for={@form}
              id="new-study"
              phx-change="validate"
              phx-submit="create"
              class="space-y-1"
            >
              <.input field={@form[:name]} label="Product name" required />
              <.input
                field={@form[:description]}
                type="textarea"
                label="What it does and for whom"
                rows="4"
                required
              />
              <.input field={@form[:url]} label="Website (optional)" placeholder="https://" />
              <.input field={@form[:price]} label="Price (optional)" placeholder="₹499/month" />
              <div class="grid grid-cols-2 gap-3">
                <.input field={@form[:budget]} type="number" label="Call budget" min="1" />
                <.input
                  field={@form[:adapter]}
                  type="select"
                  label="Model"
                  options={[{"Default (#{@default_adapter})", ""} | Enum.map(@adapters, &{&1, &1})]}
                />
              </div>
              <button class="btn btn-primary w-full mt-2" phx-disable-with="Starting…">
                Start study
              </button>
            </.form>
          </div>

          <form
            id="default-adapter"
            phx-change="set_default_adapter"
            class="rounded-box border border-base-300 p-5 space-y-2"
          >
            <label for="default-adapter-select" class="font-semibold text-sm">
              Default model backend
            </label>
            <select id="default-adapter-select" name="adapter" class="select select-sm w-full">
              <option :for={a <- @adapters} value={a} selected={a == @default_adapter}>{a}</option>
            </select>
            <p class="text-xs text-base-content/60">
              Subscription CLIs (Claude Code, Codex, Cursor, Gemini) run on your own plan. <.link
                navigate={~p"/usage"}
                class="link"
              >Check which are ready</.link>.
            </p>
          </form>
        </aside>
      </div>
    </Layouts.app>
    """
  end
end
