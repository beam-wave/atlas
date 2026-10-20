defmodule Atlas.LLM.Adapters.CodexCLI do
  @moduledoc """
  OpenAI Codex CLI (`codex exec`), billed to the user's ChatGPT plan once
  they have run `codex login`.

  Runs read-only in a scratch directory and reads the prompt from stdin
  (`-`). Output is the JSONL event stream from `--json`.

  Config keys: `:executable` (default `"codex"`), `:model`, `:timeout`,
  `:web_args` (default none; set e.g. `["--search"]` if your version supports
  it), `:extra_args`, `:env`.
  """
  @behaviour Atlas.LLM.Adapter

  alias Atlas.LLM.Adapters.CLI
  alias Atlas.LLM.{Request, Response}

  @impl true
  def complete(%Request{} = req, opts) do
    opts = Keyword.put_new(opts, :executable, "codex")

    args =
      ["exec", "--json", "--skip-git-repo-check", "--sandbox", "read-only"] ++
        CLI.model_args(req.model || opts[:model], "--model") ++
        if(req.allow_web, do: opts[:web_args] || [], else: []) ++ ["-"]

    with {:ok, out} <- CLI.run(req, opts, args) do
      parse(out)
    end
  end

  @doc """
  Parses `codex exec --json` output. Handles both the current event shape
  (`item.completed` / `turn.completed`) and the older `msg` envelope.
  """
  def parse(jsonl) do
    events =
      jsonl
      |> String.split("\n", trim: true)
      |> Enum.flat_map(fn line ->
        case Jason.decode(line) do
          {:ok, %{} = event} -> [event]
          _ -> []
        end
      end)

    messages = for e <- events, text = agent_text(e), do: text
    usage = events |> Enum.map(&usage/1) |> Enum.reject(&is_nil/1) |> List.last()
    error = Enum.find_value(events, &error_message/1)

    cond do
      messages != [] ->
        {:ok,
         %Response{
           text: List.last(messages),
           tokens_in: usage && usage["input_tokens"],
           tokens_out: usage && usage["output_tokens"],
           raw: events
         }}

      error ->
        {:error, {:codex_error, error}}

      true ->
        {:error, {:unexpected_codex_output, String.slice(jsonl, 0, 500)}}
    end
  end

  defp agent_text(%{"type" => "item.completed", "item" => %{"type" => t, "text" => text}})
       when t in ["agent_message", "assistant_message"],
       do: text

  defp agent_text(%{"msg" => %{"type" => "agent_message", "message" => text}}), do: text
  defp agent_text(_), do: nil

  defp usage(%{"type" => "turn.completed", "usage" => usage}), do: usage

  defp usage(%{"msg" => %{"type" => "token_count"} = msg}),
    do: msg["info"]["total_token_usage"] || msg

  defp usage(_), do: nil

  defp error_message(%{"type" => "turn.failed", "error" => %{"message" => m}}), do: m
  defp error_message(%{"type" => "error", "message" => m}), do: m
  defp error_message(%{"msg" => %{"type" => "error", "message" => m}}), do: m
  defp error_message(_), do: nil

  @impl true
  def check(opts) do
    CLI.check(
      Keyword.put_new(opts, :executable, "codex"),
      "uses your ChatGPT plan (run `codex login` once)"
    )
  end
end
