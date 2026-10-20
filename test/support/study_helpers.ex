defmodule Atlas.StudyHelpers do
  @moduledoc "Helpers for driving a study coordinator in tests."
  import ExUnit.Assertions

  alias Atlas.Studies

  @doc "Waits until the study reaches `state` and its coordinator is idle."
  def await_state(study_id, state, timeout \\ 10_000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_await(study_id, state, deadline)
  end

  defp do_await(study_id, state, deadline) do
    study = Studies.get_study!(study_id)

    idle? =
      case Atlas.Study.Coordinator.status(study_id) do
        %{busy: busy} -> not busy
        {:error, :not_running} -> true
      end

    cond do
      study.state == state and idle? ->
        study

      study.state == "failed" and state != "failed" ->
        flunk("study failed in #{study.failed_state}: #{study.last_error}")

      System.monotonic_time(:millisecond) > deadline ->
        flunk("timed out waiting for #{state}; study is in #{study.state}")

      true ->
        Process.sleep(20)
        do_await(study_id, state, deadline)
    end
  end

  @doc "Polls `fun` until it returns truthy (or gives up after `timeout` ms)."
  def eventually(fun, timeout \\ 5_000) do
    deadline = System.monotonic_time(:millisecond) + timeout

    Stream.repeatedly(fn -> fun.() end)
    |> Enum.find(fn result ->
      result || System.monotonic_time(:millisecond) > deadline || (Process.sleep(10) && false)
    end)
  end

  @doc "Stops all study coordinators so the sandbox owner can exit cleanly."
  def stop_all_studies do
    for {_, pid, _, _} <- DynamicSupervisor.which_children(Atlas.Study.Supervisor) do
      DynamicSupervisor.terminate_child(Atlas.Study.Supervisor, pid)
    end
  end
end
