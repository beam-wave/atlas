defmodule Atlas.Study.Supervisor do
  @moduledoc """
  `DynamicSupervisor` holding one subtree per study. A crash stays inside its
  own study.
  """
  use DynamicSupervisor

  def start_link(opts), do: DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts), do: DynamicSupervisor.init(strategy: :one_for_one)

  @doc "Starts the study's subtree unless it is already running."
  def ensure_started(study_id) do
    case Registry.lookup(Atlas.Study.Registry, {:coordinator, study_id}) do
      [{pid, _}] ->
        {:ok, pid}

      [] ->
        case DynamicSupervisor.start_child(__MODULE__, {Atlas.Study.Tree, study_id: study_id}) do
          {:ok, _tree} -> coordinator_pid(study_id)
          {:error, {:already_started, _}} -> coordinator_pid(study_id)
          error -> error
        end
    end
  end

  def stop(study_id) do
    case Registry.lookup(Atlas.Study.Registry, {:tree, study_id}) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(__MODULE__, pid)
      [] -> :ok
    end
  end

  def running?(study_id),
    do: Registry.lookup(Atlas.Study.Registry, {:coordinator, study_id}) != []

  defp coordinator_pid(study_id) do
    case Registry.lookup(Atlas.Study.Registry, {:coordinator, study_id}) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :coordinator_not_started}
    end
  end
end

defmodule Atlas.Study.Tree do
  @moduledoc """
  A study's subtree: a `Task.Supervisor` for its agents and the coordinator.
  The coordinator is transient: closing a study stops it normally, and the
  tree goes with it.
  """
  use Supervisor

  def child_spec(opts) do
    %{
      id: {__MODULE__, opts[:study_id]},
      start: {__MODULE__, :start_link, [opts]},
      restart: :temporary,
      type: :supervisor
    }
  end

  def start_link(opts) do
    study_id = Keyword.fetch!(opts, :study_id)

    Supervisor.start_link(__MODULE__, study_id,
      name: {:via, Registry, {Atlas.Study.Registry, {:tree, study_id}}}
    )
  end

  @impl true
  def init(study_id) do
    task_sup = {:via, Registry, {Atlas.Study.Registry, {:tasks, study_id}}}

    children = [
      {Task.Supervisor, name: task_sup},
      {Atlas.Study.Coordinator, study_id: study_id, task_sup: task_sup}
    ]

    Supervisor.init(children, strategy: :rest_for_one, auto_shutdown: :any_significant)
  end
end
