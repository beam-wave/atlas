defmodule Atlas.LLM.Adapters.Mock do
  @moduledoc """
  Deterministic offline adapter. Lets the whole study loop run in CI and lets
  new users try Atlas without any subscription.

  Resolution order for a request:

    1. a stub registered for the calling process (or one of its `$callers`),
       then a global stub;
    2. the agent module's `mock_output/1` (passed in `metadata.agent`), encoded
       as JSON;
    3. an echo of the prompt.
  """
  @behaviour Atlas.LLM.Adapter

  alias Atlas.LLM.{Request, Response}

  @table __MODULE__

  @impl true
  def complete(%Request{} = req, _opts) do
    case find_stub() do
      nil -> {:ok, response(default_text(req))}
      fun -> run_stub(fun, req)
    end
  end

  defp run_stub(fun, req) do
    case fun.(req) do
      {:error, _} = error -> error
      {:ok, text} when is_binary(text) -> {:ok, response(text)}
      text when is_binary(text) -> {:ok, response(text)}
      %{} = map -> {:ok, response(Jason.encode!(map))}
    end
  end

  defp response(text) do
    %Response{text: text, tokens_in: 0, tokens_out: 0, cost_usd: 0.0, model: "mock"}
  end

  defp default_text(%Request{metadata: %{agent: agent, input: input}}) when is_atom(agent) do
    Code.ensure_loaded(agent)

    if function_exported?(agent, :mock_output, 1),
      do: Jason.encode!(agent.mock_output(input)),
      else: "{}"
  end

  defp default_text(%Request{prompt: prompt}), do: Jason.encode!(%{"echo" => prompt})

  @impl true
  def check(_opts), do: {:ok, "built in; returns canned outputs (no model, no cost)"}

  ## Stubs (see Atlas.LLMStub in test/support for the test-facing helpers)

  @doc "Registers a stub under a pid (matched with `$callers`) or `:global`."
  def register_stub(key, fun) when is_function(fun, 1) do
    ensure_table()
    :ets.insert(@table, {key, fun})
    :ok
  end

  def unregister_stub(key) do
    if :ets.whereis(@table) != :undefined, do: :ets.delete(@table, key)
    :ok
  end

  defp find_stub do
    if :ets.whereis(@table) == :undefined do
      nil
    else
      [self() | Process.get(:"$callers", [])]
      |> Enum.find_value(fn pid ->
        case :ets.lookup(@table, pid) do
          [{_, fun}] -> fun
          [] -> nil
        end
      end)
      |> Kernel.||(
        case :ets.lookup(@table, :global) do
          [{_, fun}] -> fun
          [] -> nil
        end
      )
    end
  end

  @doc "Creates the stub table. Called once at boot so it outlives any test."
  def ensure_table do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, :set])
    end

    :ok
  rescue
    ArgumentError -> :ok
  end
end
