defmodule Atlas.LLM.RateLimiter do
  @moduledoc """
  Gatekeeper for every model call:

    * global kill switch (`Atlas.Settings`) halts all agents immediately;
    * per-study budget, spent atomically in the database;
    * a concurrency cap so a subscription CLI is not flooded (CLIs are slow
      and subscriptions rate-limit).

  Slots are released when the holder calls `release/0` or dies.
  """
  use GenServer

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc """
  Runs `fun` inside a slot. Returns `{:error, :kill_switch}`,
  `{:error, :budget_exhausted}` or `{:error, :queue_timeout}` without calling
  `fun` when the call may not go ahead.
  """
  def with_slot(study_id, fun, opts \\ []) do
    with :ok <- check_kill_switch(),
         :ok <- Atlas.Studies.consume_call(study_id),
         :ok <- acquire(opts[:queue_timeout] || queue_timeout()) do
      try do
        fun.()
      after
        release()
      end
    end
  end

  def acquire(timeout) do
    GenServer.call(__MODULE__, :acquire, timeout)
  catch
    :exit, {:timeout, _} ->
      GenServer.cast(__MODULE__, {:cancel, self()})
      {:error, :queue_timeout}
  end

  def release, do: GenServer.call(__MODULE__, :release)

  def status, do: GenServer.call(__MODULE__, :status)

  def set_max_concurrency(n) when is_integer(n) and n > 0,
    do: GenServer.call(__MODULE__, {:set_max, n})

  defp check_kill_switch do
    if Atlas.Settings.kill_switch?(), do: {:error, :kill_switch}, else: :ok
  end

  defp queue_timeout, do: Application.get_env(:atlas, Atlas.LLM, [])[:queue_timeout] || 600_000

  ## Server

  @impl true
  def init(opts) do
    max =
      opts[:max_concurrency] || Application.get_env(:atlas, Atlas.LLM, [])[:max_concurrency] || 3

    {:ok, %{max: max, holders: %{}, queue: :queue.new()}}
  end

  @impl true
  def handle_call(:acquire, {pid, _} = from, state) do
    if map_size(state.holders) < state.max do
      {:reply, :ok, grant(state, pid)}
    else
      {:noreply, %{state | queue: :queue.in(from, state.queue)}}
    end
  end

  def handle_call(:release, {pid, _}, state), do: {:reply, :ok, state |> drop(pid) |> dequeue()}

  def handle_call(:status, _from, state) do
    {:reply, %{max: state.max, running: map_size(state.holders), queued: :queue.len(state.queue)},
     state}
  end

  def handle_call({:set_max, n}, _from, state), do: {:reply, :ok, dequeue(%{state | max: n})}

  @impl true
  def handle_cast({:cancel, pid}, state) do
    queue = :queue.filter(fn {p, _} -> p != pid end, state.queue)
    {:noreply, state |> drop(pid) |> Map.put(:queue, queue) |> dequeue()}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _}, state) do
    {:noreply, state |> drop(pid) |> dequeue()}
  end

  defp grant(state, pid) do
    ref = Process.monitor(pid)
    %{state | holders: Map.put(state.holders, pid, ref)}
  end

  defp drop(state, pid) do
    case Map.pop(state.holders, pid) do
      {nil, _} ->
        state

      {ref, holders} ->
        Process.demonitor(ref, [:flush])
        %{state | holders: holders}
    end
  end

  defp dequeue(state) do
    if map_size(state.holders) < state.max do
      case :queue.out(state.queue) do
        {{:value, {pid, _} = from}, queue} ->
          if Process.alive?(pid) do
            GenServer.reply(from, :ok)
            dequeue(grant(%{state | queue: queue}, pid))
          else
            dequeue(%{state | queue: queue})
          end

        {:empty, _} ->
          state
      end
    else
      state
    end
  end
end
