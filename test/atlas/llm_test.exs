defmodule Atlas.LLMTest do
  use Atlas.DataCase, async: false

  import Atlas.Fixtures

  alias Atlas.{LLM, LLMStub, Settings, Studies, Usage}
  alias Atlas.LLM.{RateLimiter, Request}

  setup do
    on_exit(fn ->
      if Settings.kill_switch?(), do: Settings.release_kill_switch()
      if Settings.get("default_adapter"), do: Settings.put("default_adapter", nil)
    end)
  end

  defp req(study, attrs \\ %{}),
    do: struct(%Request{prompt: "hi", study_id: study && study.id, agent: "test"}, attrs)

  test "routes to the study's adapter and records the call" do
    study = study_fixture()
    LLMStub.stub(fn _ -> ~s({"x":1}) end)

    assert {:ok, %{text: ~s({"x":1})}} = LLM.complete(req(study))
    assert [%{agent: "test", calls: 1, errors: 0}] = Usage.by_agent(study.id)
    assert Studies.get_study!(study.id).calls_used == 1
  end

  test "records failures too" do
    study = study_fixture()
    LLMStub.stub(fn _ -> {:error, :boom} end)
    assert {:error, :boom} = LLM.complete(req(study))
    assert [%{calls: 1, errors: 1}] = Usage.by_agent(study.id)
  end

  test "stops at the study budget" do
    study = study_fixture(%{budget: 2})
    LLMStub.stub(fn _ -> "{}" end)

    assert {:ok, _} = LLM.complete(req(study))
    assert {:ok, _} = LLM.complete(req(study))
    assert {:error, :budget_exhausted} = LLM.complete(req(study))
    assert Studies.get_study!(study.id).calls_used == 2
  end

  test "the kill switch halts every call" do
    study = study_fixture()
    Settings.engage_kill_switch()
    assert {:error, :kill_switch} = LLM.complete(req(study))
    assert Studies.get_study!(study.id).calls_used == 0
    Settings.release_kill_switch()
    LLMStub.stub(fn _ -> "{}" end)
    assert {:ok, _} = LLM.complete(req(study))
  end

  test "resolves adapters: explicit, study, setting, config" do
    study = study_fixture(%{adapter: "codex_cli"})
    assert LLM.resolve_adapter(study.id, "cursor_cli") == "cursor_cli"
    assert LLM.resolve_adapter(study.id) == "codex_cli"
    assert LLM.resolve_adapter(nil) == "mock"
    Settings.put("default_adapter", "gemini_cli")
    assert LLM.resolve_adapter(nil) == "gemini_cli"
  end

  test "unknown adapters and crashing adapters return errors" do
    assert {:error, {:unknown_adapter, "nope"}} = LLM.complete(req(nil), adapter: "nope")
    LLMStub.stub(fn _ -> raise "kaboom" end)
    assert {:error, {:adapter_crashed, "kaboom"}} = LLM.complete(req(nil))
  end

  test "the mock adapter falls back to an agent's canned output" do
    r = %Request{
      prompt: "x",
      agent: "skeptic",
      metadata: %{agent: Atlas.Agents.Skeptic, input: %{}}
    }

    assert {:ok, %{text: text}} = LLM.complete(r)
    assert %{"verdict" => "PASS"} = Jason.decode!(text)
  end

  test "doctor checks every adapter" do
    results = Map.new(LLM.doctor())
    assert Map.keys(results) == LLM.adapter_names()
    assert {:ok, _} = results["mock"]
    assert {:ok, _} = results["anthropic_api"]
  end

  describe "RateLimiter" do
    test "caps concurrency and queues the rest" do
      :ok = RateLimiter.set_max_concurrency(2)
      on_exit(fn -> RateLimiter.set_max_concurrency(4) end)

      parent = self()

      tasks =
        for i <- 1..4 do
          Task.async(fn ->
            RateLimiter.with_slot(nil, fn ->
              send(parent, {:running, i, RateLimiter.status().running})
              Process.sleep(100)
              :done
            end)
          end)
        end

      assert Enum.map(tasks, &Task.await/1) == [:done, :done, :done, :done]

      running = for _ <- 1..4, do: receive(do: ({:running, _, n} -> n))
      assert Enum.max(running) <= 2
      assert %{running: 0, queued: 0} = RateLimiter.status()
    end

    test "frees the slot when the holder crashes" do
      :ok = RateLimiter.set_max_concurrency(1)
      on_exit(fn -> RateLimiter.set_max_concurrency(4) end)

      parent = self()

      {pid, ref} =
        spawn_monitor(fn ->
          RateLimiter.acquire(1_000)
          send(parent, :acquired)
          Process.sleep(:infinity)
        end)

      assert_receive :acquired, 2_000
      assert %{running: 1} = RateLimiter.status()
      Process.exit(pid, :kill)
      assert_receive {:DOWN, ^ref, _, _, _}
      # The limiter sees the DOWN asynchronously; a queued caller still gets the slot.
      assert :ok = RateLimiter.with_slot(nil, fn -> :ok end, queue_timeout: 2_000)
    end

    test "times out when no slot frees up" do
      :ok = RateLimiter.set_max_concurrency(1)
      on_exit(fn -> RateLimiter.set_max_concurrency(4) end)

      parent = self()

      holder =
        Task.async(fn ->
          RateLimiter.with_slot(nil, fn ->
            send(parent, :holding)
            receive do: (:release -> :ok)
          end)
        end)

      assert_receive :holding, 2_000

      assert {:error, :queue_timeout} =
               RateLimiter.with_slot(nil, fn -> :never end, queue_timeout: 50)

      send(holder.pid, :release)
      Task.await(holder)
      assert %{queued: 0} = RateLimiter.status()
    end
  end
end
