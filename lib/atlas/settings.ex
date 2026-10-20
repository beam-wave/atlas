defmodule Atlas.Settings do
  @moduledoc """
  Runtime settings persisted in the database and cached in `:persistent_term`
  (read on every model call, written rarely): the kill switch and the default
  LLM adapter.
  """
  alias Atlas.Repo

  defmodule Setting do
    @moduledoc false
    use Ecto.Schema

    @primary_key {:key, :string, autogenerate: false}
    schema "settings" do
      field :value, :map
      timestamps(type: :utc_datetime)
    end
  end

  @defaults %{"kill_switch" => false, "default_adapter" => nil}

  def get(key) when is_binary(key) do
    :persistent_term.get({__MODULE__, key}, Map.get(@defaults, key))
  end

  def put(key, value) when is_binary(key) do
    now = DateTime.utc_now(:second)

    Repo.insert!(%Setting{key: key, value: %{"v" => value}, inserted_at: now, updated_at: now},
      on_conflict: [set: [value: %{"v" => value}, updated_at: now]],
      conflict_target: :key
    )

    :persistent_term.put({__MODULE__, key}, value)
    Phoenix.PubSub.broadcast(Atlas.PubSub, "settings", {:setting, key, value})
    :ok
  end

  def subscribe, do: Phoenix.PubSub.subscribe(Atlas.PubSub, "settings")

  @doc "Loads persisted settings into the cache. Called at boot."
  def load do
    for %Setting{key: key, value: %{"v" => v}} <- Repo.all(Setting) do
      :persistent_term.put({__MODULE__, key}, v)
    end

    :ok
  rescue
    # The table may not exist yet on a fresh checkout before migrations.
    _ -> :ok
  end

  def kill_switch?, do: get("kill_switch") == true
  def engage_kill_switch, do: put("kill_switch", true)
  def release_kill_switch, do: put("kill_switch", false)
end
