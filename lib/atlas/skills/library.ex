defmodule Atlas.Skills.Library do
  @moduledoc """
  Loads `priv/skills/**/*.md` into ETS and keeps it current.

  Hot reload polls file mtimes (no native file-watcher dependency, so setup
  stays a plain `mix setup`). Edits made through `write/2` apply immediately;
  edits made in an editor apply within one poll interval. Invalid files are
  skipped and reported by `errors/0`; the last valid version stays loaded.

  Which skills an agent loads comes from `skill_map.json` in the same
  directory.
  """
  use GenServer
  require Logger

  alias Atlas.Skills.Skill

  @table __MODULE__

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  ## Reads go straight to ETS.

  def get(name) do
    case :ets.lookup(@table, {:skill, name}) do
      [{_, skill}] -> {:ok, skill}
      [] -> {:error, :not_found}
    end
  end

  def all do
    @table
    |> :ets.match_object({{:skill, :_}, :_})
    |> Enum.map(&elem(&1, 1))
    |> Enum.sort_by(&{&1.group, &1.name})
  end

  def errors do
    case :ets.lookup(@table, :errors) do
      [{_, errors}] -> errors
      [] -> %{}
    end
  end

  def skill_map do
    case :ets.lookup(@table, :skill_map) do
      [{_, map}] -> map
      [] -> %{}
    end
  end

  @doc "Skills for an agent, in skill-map order, falling back to `defaults`."
  def for_agent(agent_name, defaults \\ []) do
    names = Map.get(skill_map(), agent_name, defaults)

    Enum.flat_map(names, fn name ->
      case get(name) do
        {:ok, skill} ->
          [skill]

        {:error, :not_found} ->
          Logger.warning("skill #{name} mapped to #{agent_name} is not loaded")
          []
      end
    end)
  end

  @doc "Validates and saves a skill's full file content, then reloads it."
  def write(name, content) do
    GenServer.call(__MODULE__, {:write, name, content})
  end

  def reload, do: GenServer.call(__MODULE__, :reload)

  def dir, do: GenServer.call(__MODULE__, :dir)

  ## Server

  @impl true
  def init(opts) do
    :ets.new(@table, [:named_table, :protected, :set, read_concurrency: true])
    dir = opts[:dir] || default_dir()
    poll = Keyword.get(opts, :poll_ms, Application.get_env(:atlas, :skills_poll_ms, 2000))
    state = %{dir: dir, poll: poll, mtimes: %{}}
    state = load(state)
    schedule(state)
    {:ok, state}
  end

  def default_dir do
    System.get_env("ATLAS_SKILLS_DIR") || Application.get_env(:atlas, :skills_dir) ||
      Application.app_dir(:atlas, "priv/skills")
  end

  @impl true
  def handle_call(:reload, _from, state), do: {:reply, :ok, load(%{state | mtimes: %{}})}
  def handle_call(:dir, _from, state), do: {:reply, state.dir, state}

  def handle_call({:write, name, content}, _from, state) do
    with {:ok, existing} <- get(name),
         {:ok, _} <- Skill.parse(content, existing.path),
         :ok <- File.write(existing.path, content) do
      state = load(state)
      Phoenix.PubSub.broadcast(Atlas.PubSub, "skills", {:skill_changed, name})
      {:reply, :ok, state}
    else
      {:error, :not_found} -> {:reply, {:error, :not_found}, state}
      {:error, reasons} when is_list(reasons) -> {:reply, {:error, reasons}, state}
      {:error, posix} -> {:reply, {:error, [inspect(posix)]}, state}
    end
  end

  @impl true
  def handle_info(:poll, state) do
    state = if changed?(state), do: load(state), else: state
    schedule(state)
    {:noreply, state}
  end

  defp schedule(%{poll: ms}) when is_integer(ms) and ms > 0,
    do: Process.send_after(self(), :poll, ms)

  defp schedule(_), do: :ok

  defp files(dir), do: Path.wildcard(Path.join(dir, "**/*.md"))

  defp mtimes(dir) do
    files = files(dir) ++ [Path.join(dir, "skill_map.json")]

    Map.new(files, fn f ->
      case File.stat(f, time: :posix) do
        {:ok, %{mtime: m}} -> {f, m}
        _ -> {f, nil}
      end
    end)
  end

  defp changed?(state), do: mtimes(state.dir) != state.mtimes

  defp load(state) do
    loaded =
      for path <- files(state.dir), into: %{} do
        result =
          with {:ok, content} <- File.read(path) do
            Skill.parse(content, path)
          end

        {path, result}
      end

    errors =
      for {path, {:error, reasons}} <- loaded, into: %{} do
        {Path.relative_to(path, state.dir), List.wrap(reasons)}
      end

    valid = for {path, {:ok, skill}} <- loaded, do: %{skill | group: group(path, state.dir)}
    valid_names = MapSet.new(valid, & &1.name)

    # Keep the last good version of a file that is now invalid.
    stale =
      for {{:skill, name}, _} <- :ets.match_object(@table, {{:skill, :_}, :_}),
          not MapSet.member?(valid_names, name),
          File.exists?(skill_path(name)),
          do: name

    for {{:skill, name}, _} = obj <- :ets.match_object(@table, {{:skill, :_}, :_}),
        not MapSet.member?(valid_names, name),
        name not in stale do
      :ets.delete_object(@table, obj)
    end

    Enum.each(valid, &:ets.insert(@table, {{:skill, &1.name}, &1}))
    :ets.insert(@table, {:errors, errors})
    :ets.insert(@table, {:skill_map, read_skill_map(state.dir)})

    if errors != %{}, do: Logger.warning("invalid skills skipped: #{inspect(errors)}")

    %{state | mtimes: mtimes(state.dir)}
  end

  defp skill_path(name) do
    case :ets.lookup(@table, {:skill, name}) do
      [{_, %Skill{path: path}}] -> path
      _ -> ""
    end
  end

  defp group(path, dir) do
    case Path.split(Path.relative_to(path, dir)) do
      [group, _file] -> group
      _ -> "root"
    end
  end

  defp read_skill_map(dir) do
    with {:ok, body} <- File.read(Path.join(dir, "skill_map.json")),
         {:ok, %{} = map} <- Jason.decode(body) do
      Map.reject(map, fn {k, _} -> String.starts_with?(k, "_") end)
    else
      _ -> %{}
    end
  end
end
