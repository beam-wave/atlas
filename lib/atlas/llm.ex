defmodule Atlas.LLM do
  @moduledoc """
  Entry point for model calls. Picks the adapter, goes through the rate
  limiter (kill switch, budget, concurrency) and records every call in
  `llm_calls`.

  Adapters, by name:

  | name            | backend                                   | billing                |
  |-----------------|-------------------------------------------|------------------------|
  | `claude_cli`    | `claude -p` (Claude Code)                 | Claude subscription    |
  | `codex_cli`     | `codex exec` (OpenAI Codex CLI)           | ChatGPT plan           |
  | `cursor_cli`    | `cursor-agent -p` (Cursor CLI)            | Cursor subscription    |
  | `gemini_cli`    | `gemini -p` (Gemini CLI)                  | Google account         |
  | `anthropic_api` | Claude Messages API                       | API key                |
  | `mock`          | canned outputs                            | free, offline          |

  The adapter for a call is, in order: `opts[:adapter]`, the study's own
  adapter, the default set in the dashboard, `ATLAS_LLM_ADAPTER`, then the
  configured `:default_adapter`.
  """
  require Logger

  alias Atlas.LLM.{Adapters, RateLimiter, Request}

  @adapters %{
    "claude_cli" => Adapters.ClaudeCLI,
    "codex_cli" => Adapters.CodexCLI,
    "cursor_cli" => Adapters.CursorCLI,
    "gemini_cli" => Adapters.GeminiCLI,
    "anthropic_api" => Adapters.AnthropicAPI,
    "mock" => Adapters.Mock
  }

  def adapter_names, do: Map.keys(@adapters) |> Enum.sort()

  def adapter_module(name), do: Map.get(@adapters, name)

  @doc "Runs a request. See the module doc for adapter resolution."
  @spec complete(Request.t(), keyword()) :: {:ok, Atlas.LLM.Response.t()} | {:error, term()}
  def complete(%Request{} = req, opts \\ []) do
    name = resolve_adapter(req.study_id, opts[:adapter])

    case adapter_module(name) do
      nil ->
        {:error, {:unknown_adapter, name}}

      module ->
        adapter_opts = Keyword.merge(adapter_config(name), opts[:adapter_opts] || [])

        RateLimiter.with_slot(req.study_id, fn ->
          started = System.monotonic_time(:millisecond)
          result = safe_complete(module, req, adapter_opts)
          record(req, name, result, System.monotonic_time(:millisecond) - started)
          result
        end)
    end
  end

  defp safe_complete(module, req, opts) do
    module.complete(req, opts)
  rescue
    e -> {:error, {:adapter_crashed, Exception.message(e)}}
  end

  defp record(req, adapter, result, duration_ms) do
    base = %{study_id: req.study_id, agent: req.agent, adapter: adapter, duration_ms: duration_ms}

    attrs =
      case result do
        {:ok, resp} ->
          Map.merge(base, %{
            outcome: "ok",
            model: resp.model || req.model,
            tokens_in: resp.tokens_in,
            tokens_out: resp.tokens_out,
            cost_usd: resp.cost_usd
          })

        {:error, reason} ->
          Logger.warning(
            "LLM call failed adapter=#{adapter} agent=#{req.agent}: #{inspect(reason)}"
          )

          Map.merge(base, %{
            outcome: "error",
            model: req.model,
            error: inspect(reason) |> String.slice(0, 2000)
          })
      end

    Atlas.Usage.record(attrs)
  end

  @doc "The adapter name that would be used for a study."
  def resolve_adapter(study_id \\ nil, explicit \\ nil) do
    explicit ||
      study_adapter(study_id) ||
      Atlas.Settings.get("default_adapter") ||
      System.get_env("ATLAS_LLM_ADAPTER") ||
      config()[:default_adapter] ||
      "claude_cli"
  end

  defp study_adapter(nil), do: nil

  defp study_adapter(study_id) do
    case Atlas.Repo.get(Atlas.Studies.Study, study_id) do
      %{adapter: adapter} -> adapter
      nil -> nil
    end
  end

  def adapter_config(name) do
    (config()[:adapters] || %{}) |> Map.get(name, []) |> Keyword.new()
  end

  defp config, do: Application.get_env(:atlas, __MODULE__, [])

  @doc "Checks every adapter. Returns `[{name, {:ok | :error, message}}]`."
  def doctor do
    for name <- adapter_names() do
      {name, adapter_module(name).check(adapter_config(name))}
    end
  end
end
