defmodule Atlas.Live.SubscriptionCLIsTest do
  @moduledoc """
  Real calls to the subscription CLIs installed on this machine. Excluded by
  default because they spend your plan's quota:

      mix test --only live

  Each test skips itself when its CLI is not installed.
  """
  use Atlas.DataCase, async: false

  alias Atlas.Agents.{Intake, Runner}
  alias Atlas.LLM

  @moduletag :live
  @moduletag timeout: 300_000

  @adapters [
    {"claude_cli", "claude"},
    {"codex_cli", "codex"},
    {"cursor_cli", Atlas.LLM.Adapters.CursorCLI.default_executable()},
    {"gemini_cli", "gemini"}
  ]

  for {adapter, exe} <- @adapters do
    @adapter adapter
    @exe exe

    test "#{adapter} answers a raw prompt" do
      if System.find_executable(@exe) do
        module = LLM.adapter_module(@adapter)
        req = %LLM.Request{prompt: ~s(Reply with exactly {"ok": true} and nothing else.)}
        assert {:ok, %{text: text}} = module.complete(req, LLM.adapter_config(@adapter))
        assert {:ok, %{"ok" => true}} = Atlas.Agents.JSON.extract(text)
      else
        IO.puts("skipping #{@adapter}: #{@exe} not installed")
      end
    end

    test "#{adapter} produces a schema-valid agent output" do
      if System.find_executable(@exe) do
        input = %{
          product: %{
            name: "LedgerLite",
            description: "AI bookkeeping that prepares GST returns for Indian freelancers."
          }
        }

        assert {:ok, %Intake{} = brief, _meta} = Runner.run(Intake, input, %{adapter: @adapter})
        assert brief.assumptions != []
      else
        IO.puts("skipping #{@adapter}: #{@exe} not installed")
      end
    end
  end
end
