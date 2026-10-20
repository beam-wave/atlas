defmodule Atlas.LLMStub do
  @moduledoc """
  Test helpers for the mock adapter.

      Atlas.LLMStub.stub(fn req -> ~s({"ok": true}) end)

  `stub/1` applies to the test process and Tasks it starts; `stub_global/1`
  applies to every process (use only in `async: false` tests, e.g. when a
  study coordinator makes the calls).
  """
  import ExUnit.Callbacks, only: [on_exit: 1]

  alias Atlas.LLM.Adapters.Mock

  def stub(fun) do
    owner = self()
    Mock.register_stub(owner, fun)
    on_exit(fn -> Mock.unregister_stub(owner) end)
  end

  def stub_global(fun) do
    Mock.register_stub(:global, fun)
    on_exit(fn -> Mock.unregister_stub(:global) end)
  end

  @doc "Stub that answers per agent name, falling back to the agent's mock output."
  def stub_agents(responses, scope \\ :local) do
    fun = fn req ->
      case Map.fetch(responses, req.agent) do
        {:ok, f} when is_function(f, 1) -> f.(req)
        {:ok, value} -> value
        :error -> Jason.encode!(req.metadata.agent.mock_output(req.metadata.input))
      end
    end

    if scope == :global, do: stub_global(fun), else: stub(fun)
  end
end
