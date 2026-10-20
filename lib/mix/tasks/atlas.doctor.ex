defmodule Mix.Tasks.Atlas.Doctor do
  @shortdoc "Checks which model backends (Claude, Codex, Cursor, Gemini, API) are ready"
  @moduledoc """
  Reports which model backends Atlas can use on this machine.

      mix atlas.doctor
      mix atlas.doctor --ping claude_cli   # also sends one tiny prompt

  Subscription CLIs must be installed and logged in once:

    * Claude Code — `npm i -g @anthropic-ai/claude-code`, then run `claude`
    * Codex CLI — `npm i -g @openai/codex`, then `codex login`
    * Cursor CLI — `curl https://cursor.com/install -fsS | bash`, then `cursor-agent login`
    * Gemini CLI — `npm i -g @google/gemini-cli`, then run `gemini`
  """
  use Mix.Task

  @impl true
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [ping: :string])
    Mix.Task.run("app.config")
    {:ok, _} = Application.ensure_all_started(:req)

    Mix.shell().info("Model backends:\n")

    for name <- Atlas.LLM.adapter_names() do
      module = Atlas.LLM.adapter_module(name)

      case module.check(Atlas.LLM.adapter_config(name)) do
        {:ok, msg} -> Mix.shell().info("  [ok]   #{String.pad_trailing(name, 14)} #{msg}")
        {:error, msg} -> Mix.shell().info("  [--]   #{String.pad_trailing(name, 14)} #{msg}")
      end
    end

    Mix.shell().info("""

    Default: #{System.get_env("ATLAS_LLM_ADAPTER") || Application.get_env(:atlas, Atlas.LLM)[:default_adapter]}
    Change it with ATLAS_LLM_ADAPTER=<name>, per study in the dashboard, or in config/config.exs.
    """)

    if name = opts[:ping], do: ping(name)
  end

  defp ping(name) do
    module = Atlas.LLM.adapter_module(name) || Mix.raise("unknown adapter #{name}")
    Mix.shell().info("Pinging #{name}…")

    req = %Atlas.LLM.Request{
      prompt: ~s(Reply with exactly this JSON and nothing else: {"ok": true})
    }

    case module.complete(req, Atlas.LLM.adapter_config(name)) do
      {:ok, resp} -> Mix.shell().info("  reply: #{String.trim(resp.text)}")
      {:error, reason} -> Mix.shell().error("  failed: #{inspect(reason)}")
    end
  end
end
