defmodule Atlas.LLM.Adapters.CursorCLI do
  @moduledoc """
  Cursor's agent CLI (`cursor-agent -p`), billed to the user's Cursor
  subscription once they have run `cursor-agent login`.

  Config keys: `:executable` (default: `cursor-agent`, or `agent`, the name
  newer installers use, whichever is on PATH), `:model`, `:timeout`,
  `:extra_args`, `:env`.
  """
  @behaviour Atlas.LLM.Adapter

  alias Atlas.LLM.Adapters.CLI
  alias Atlas.LLM.{Request, Response}

  @impl true
  def complete(%Request{} = req, opts) do
    opts = Keyword.put_new_lazy(opts, :executable, &default_executable/0)

    args =
      ["-p", "--output-format", "json"] ++
        CLI.model_args(req.model || opts[:model], "--model")

    with {:ok, out} <- CLI.run(req, opts, args),
         {:ok, data} <- CLI.decode_json(out) do
      parse(data)
    end
  end

  @doc false
  def parse(%{"is_error" => true} = data),
    do: {:error, {:cursor_error, data["result"] || data["subtype"] || "unknown error"}}

  def parse(%{"result" => text} = data) when is_binary(text) do
    usage = data["usage"] || %{}

    {:ok,
     %Response{
       text: text,
       tokens_in: usage["inputTokens"] || usage["input_tokens"],
       tokens_out: usage["outputTokens"] || usage["output_tokens"],
       model: data["model"],
       raw: data
     }}
  end

  def parse(data), do: {:error, {:unexpected_cursor_output, data}}

  @doc false
  def default_executable do
    Enum.find(["cursor-agent", "agent"], "cursor-agent", &System.find_executable/1)
  end

  @impl true
  def check(opts) do
    CLI.check(
      Keyword.put_new_lazy(opts, :executable, &default_executable/0),
      "uses your Cursor subscription (run `cursor-agent login` once)"
    )
  end
end
