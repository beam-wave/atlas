defmodule Atlas.Study.Coordinator do
  @moduledoc """
  One `gen_statem` per study. Routes deterministically between the eight
  lifecycle states; no model decides control flow.

  Automatic states run their step as a supervised task. Human states
  (`hypothesize`, `await_data`, `verdict`) first run any agent work they need,
  then wait for an event:

  | state         | event                     | goes to                                |
  |---------------|---------------------------|----------------------------------------|
  | hypothesize   | `{:prune, segment_ids}`   | desk_research                          |
  | await_data    | `:finish_data`            | ingest_results                         |
  | verdict       | `{:continue, route}`      | hypothesize or design_tests (loop + 1) |
  | failed        | `:retry`                  | the state that failed                  |
  | any           | `:close`                  | closed                                 |

  State lives in the database, so a restarted coordinator resumes where the
  study left off. A crashed or failed step is retried once, then the study
  moves to `failed` with the error.
  """
  @behaviour :gen_statem
  require Logger

  alias Atlas.{Scoring, Studies}
  alias Atlas.Study.Steps

  @auto ~w(intake hypothesize desk_research desk_score design_tests ingest_results verdict)

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      restart: :transient,
      significant: true
    }
  end

  def start_link(opts) do
    study_id = Keyword.fetch!(opts, :study_id)
    :gen_statem.start_link(via(study_id), __MODULE__, opts, [])
  end

  def via(study_id), do: {:via, Registry, {Atlas.Study.Registry, {:coordinator, study_id}}}

  @doc "Sends a human event. Returns `:ok` or `{:error, reason}`."
  def event(study_id, event, timeout \\ 30_000) do
    :gen_statem.call(via(study_id), {:event, event}, timeout)
  catch
    :exit, {:noproc, _} -> {:error, :not_running}
  end

  def status(study_id) do
    :gen_statem.call(via(study_id), :status)
  catch
    :exit, {:noproc, _} -> {:error, :not_running}
  end

  @impl true
  def callback_mode, do: :handle_event_function

  @impl true
  def init(opts) do
    study_id = Keyword.fetch!(opts, :study_id)
    study = Studies.get_study!(study_id)

    data = %{
      study_id: study_id,
      task_sup: Keyword.fetch!(opts, :task_sup),
      task: nil,
      retries: 0,
      max_retries: Application.get_env(:atlas, :step_retries, 1)
    }

    {:ok, study.state, data, [{:next_event, :internal, :run}]}
  end

  ## Running steps

  @impl true
  def handle_event(:internal, :run, state, data) when state in @auto do
    study = Studies.get_study!(data.study_id)
    ctx = %{task_sup: data.task_sup}
    task = Task.Supervisor.async_nolink(data.task_sup, fn -> Steps.run(state, study, ctx) end)
    Studies.broadcast(data.study_id, {:running, state})
    {:keep_state, %{data | task: task}}
  end

  def handle_event(:internal, :run, _state, data), do: {:keep_state, data}

  def handle_event(:info, {ref, result}, state, %{task: %Task{ref: ref}} = data) do
    Process.demonitor(ref, [:flush])
    data = %{data | task: nil}

    case result do
      {:next, next} ->
        transition(state, next, %{}, %{data | retries: 0})

      :wait ->
        Studies.broadcast(data.study_id, {:waiting, state})
        {:keep_state, %{data | retries: 0}}

      {:error, reason} ->
        step_failed(state, reason, data)
    end
  end

  def handle_event(
        :info,
        {:DOWN, ref, :process, _pid, reason},
        state,
        %{task: %Task{ref: ref}} = data
      ) do
    step_failed(state, {:crashed, reason}, %{data | task: nil})
  end

  def handle_event(:info, _msg, _state, _data), do: :keep_state_and_data

  ## Human events

  def handle_event({:call, from}, :status, state, data) do
    {:keep_state_and_data, [{:reply, from, %{state: state, busy: data.task != nil}}]}
  end

  def handle_event({:call, from}, {:event, :close}, state, data) do
    if data.task, do: Task.shutdown(data.task, :brutal_kill)
    Atlas.Audit.log(data.study_id, "study_closed", %{from_state: state})
    persist(data.study_id, %{state: "closed"})
    {:stop_and_reply, :normal, [{:reply, from, :ok}]}
  end

  def handle_event({:call, from}, {:event, _event}, _state, %{task: %Task{}}) do
    {:keep_state_and_data, [{:reply, from, {:error, :busy}}]}
  end

  def handle_event({:call, from}, {:event, {:prune, ids}}, "hypothesize", data) do
    case Studies.prune_segments(data.study_id, ids) do
      {:ok, kept} ->
        Atlas.Audit.log(data.study_id, "segments_pruned", %{kept: kept, ids: ids})
        transition("hypothesize", "desk_research", %{}, data, [{:reply, from, :ok}])

      {:error, reason} ->
        {:keep_state_and_data, [{:reply, from, {:error, reason}}]}
    end
  end

  def handle_event({:call, from}, {:event, :finish_data}, "await_data", data) do
    case Steps.ready_for_ingest(Studies.get_study!(data.study_id)) do
      :ok -> transition("await_data", "ingest_results", %{}, data, [{:reply, from, :ok}])
      error -> {:keep_state_and_data, [{:reply, from, error}]}
    end
  end

  def handle_event({:call, from}, {:event, {:continue, route}}, "verdict", data) do
    study = Studies.get_study!(data.study_id)
    route = route || Scoring.route(study.next_move)

    if route in ["hypothesize", "design_tests"] do
      Atlas.Audit.log(data.study_id, "loop_continued", %{
        route: route,
        loop: study.loop_number + 1,
        next_move: study.next_move
      })

      transition("verdict", route, %{loop_number: study.loop_number + 1}, data, [
        {:reply, from, :ok}
      ])
    else
      {:keep_state_and_data, [{:reply, from, {:error, :invalid_route}}]}
    end
  end

  def handle_event({:call, from}, {:event, :retry}, "failed", data) do
    study = Studies.get_study!(data.study_id)
    target = study.failed_state || "intake"

    transition("failed", target, %{last_error: nil, failed_state: nil}, %{data | retries: 0}, [
      {:reply, from, :ok}
    ])
  end

  def handle_event({:call, from}, {:event, :wake}, state, _data) when state in @auto do
    {:keep_state_and_data, [{:reply, from, :ok}, {:next_event, :internal, :run}]}
  end

  def handle_event({:call, from}, {:event, event}, state, _data) do
    {:keep_state_and_data, [{:reply, from, {:error, {:not_allowed, state, event_name(event)}}}]}
  end

  ## Transitions

  defp transition(from, to, attrs, data, actions \\ []) do
    persist(data.study_id, Map.put(attrs, :state, to))
    Logger.info("study #{data.study_id}: #{from} -> #{to}")
    {:next_state, to, data, actions ++ [{:next_event, :internal, :run}]}
  end

  defp step_failed(state, reason, data) do
    if retryable?(reason) and data.retries < data.max_retries do
      Logger.warning("study #{data.study_id} step #{state} failed, retrying: #{inspect(reason)}")
      {:keep_state, %{data | retries: data.retries + 1}, [{:next_event, :internal, :run}]}
    else
      Logger.error("study #{data.study_id} step #{state} failed: #{inspect(reason)}")
      Atlas.Audit.log(data.study_id, "step_failed", %{state: state, reason: inspect(reason)})

      persist(data.study_id, %{state: "failed", failed_state: state, last_error: describe(reason)})

      {:next_state, "failed", %{data | retries: 0}}
    end
  end

  # Budget and kill switch will fail again immediately; don't burn a retry.
  defp retryable?({:llm, reason}) when reason in [:kill_switch, :budget_exhausted], do: false
  defp retryable?(reason), do: not contains?(reason, [:kill_switch, :budget_exhausted])

  defp contains?(term, atoms) when is_atom(term), do: term in atoms

  defp contains?(term, atoms) when is_tuple(term),
    do: term |> Tuple.to_list() |> Enum.any?(&contains?(&1, atoms))

  defp contains?(term, atoms) when is_list(term), do: Enum.any?(term, &contains?(&1, atoms))
  defp contains?(_, _), do: false

  defp describe(reason) do
    cond do
      contains?(reason, [:budget_exhausted]) ->
        "Model-call budget exhausted. Raise the budget, then retry."

      contains?(reason, [:kill_switch]) ->
        "Kill switch is on. Release it, then retry."

      true ->
        inspect(reason, limit: 50, printable_limit: 2000)
    end
  end

  defp persist(study_id, attrs) do
    {:ok, _} = Studies.update_study(Studies.get_study!(study_id), attrs)
  end

  defp event_name(event) when is_tuple(event), do: elem(event, 0)
  defp event_name(event), do: event
end
