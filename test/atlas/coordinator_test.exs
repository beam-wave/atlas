defmodule Atlas.CoordinatorTest do
  @moduledoc "Failure handling in the study state machine."
  use Atlas.DataCase, async: false

  import Atlas.StudyHelpers

  alias Atlas.{LLMStub, Settings, Studies, Study}

  setup do
    on_exit(fn ->
      if Settings.kill_switch?(), do: Settings.release_kill_switch()
      stop_all_studies()
    end)
  end

  defp start(attrs \\ %{}) do
    {:ok, study} =
      Study.start(
        Map.merge(%{name: "X", description: "A product description.", adapter: "mock"}, attrs)
      )

    study
  end

  test "a failing step is retried once, then the study fails with the error and can be retried" do
    {:ok, calls} = Agent.start_link(fn -> 0 end)

    LLMStub.stub_global(fn req ->
      if req.agent == "intake" do
        Agent.update(calls, &(&1 + 1))
        {:error, :upstream_down}
      else
        Jason.encode!(req.metadata.agent.mock_output(req.metadata.input))
      end
    end)

    study = start()
    study = await_state(study.id, "failed")
    assert study.failed_state == "intake"
    assert study.last_error =~ "upstream_down"
    # one attempt + one step retry
    assert Agent.get(calls, & &1) == 2
    assert [%{kind: "step_failed"}] = Atlas.Audit.list(study.id, kind: "step_failed")

    assert {:error, {:not_allowed, "failed", :prune}} = Study.prune_segments(study.id, [1])

    LLMStub.stub_global(fn req ->
      Jason.encode!(req.metadata.agent.mock_output(req.metadata.input))
    end)

    assert :ok = Study.retry(study.id)
    study = await_state(study.id, "hypothesize")
    assert study.last_error == nil
  end

  test "budget exhaustion fails fast with a readable message" do
    study = start(%{budget: 1})
    study = await_state(study.id, "failed")
    assert study.last_error =~ "budget exhausted"
    assert Studies.get_study!(study.id).calls_used == 1

    {:ok, _} = Studies.update_study(study, %{budget: 100})
    :ok = Study.retry(study.id)
    await_state(study.id, "hypothesize")
  end

  test "the kill switch halts the study" do
    Settings.engage_kill_switch()
    study = start()
    study = await_state(study.id, "failed")
    assert study.last_error =~ "Kill switch"
  end

  test "a crashing agent task is contained and reported" do
    LLMStub.stub_global(fn
      %{agent: "intake"} -> exit(:boom)
      req -> Jason.encode!(req.metadata.agent.mock_output(req.metadata.input))
    end)

    study = start()
    study = await_state(study.id, "failed")
    assert study.last_error =~ "crashed"
    # The rest of the system is unaffected.
    assert Process.whereis(Atlas.Study.Supervisor)
  end

  test "a restarted coordinator resumes from the stored state" do
    study = start()
    await_state(study.id, "hypothesize")
    proposed = Studies.list_segments(study.id, status: "proposed")

    :ok = Atlas.Study.Supervisor.stop(study.id)
    refute Study.running?(study.id)

    # Resuming does not re-run the strategist: the proposals are still there.
    assert %{state: "hypothesize"} = Study.status(study.id)
    await_state(study.id, "hypothesize")
    assert Studies.list_segments(study.id, status: "proposed") == proposed
  end

  test "closing stops the coordinator; closed studies refuse events" do
    study = start()
    await_state(study.id, "hypothesize")
    assert :ok = Study.close(study.id)
    Process.sleep(50)
    refute Study.running?(study.id)
    assert {:error, :closed} = Study.prune_segments(study.id, [1])
    assert {:error, :not_found} = Study.close(-1)
  end

  test "continue rejects unknown routes" do
    study = start()
    await_state(study.id, "hypothesize")

    assert {:error, {:not_allowed, "hypothesize", :continue}} =
             Study.continue(study.id, "anywhere")
  end

  test "deleting a study removes its data" do
    study = start()
    await_state(study.id, "hypothesize")
    {:ok, _} = Study.delete(study.id)
    assert Studies.get_study(study.id) == nil
    assert Atlas.Evidence.count(study.id) == 0
  end
end
