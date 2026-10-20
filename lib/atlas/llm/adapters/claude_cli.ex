defmodule Atlas.LLM.Adapters.ClaudeCLI do
  @moduledoc """
  Claude Code in print mode (`claude -p`), billed to the user's Claude
  subscription once they have run `claude` and logged in.

  Config keys: `:executable` (default `"claude"`), `:model`, `:timeout`,
  `:web_args` (added when an agent may browse; default allows only
  WebSearch and WebFetch), `:extra_args`, `:env`.
  """
  @behaviour Atlas.LLM.Adapter

  alias Atlas.LLM.Adapters.CLI
  alias Atlas.LLM.{Request, Response}

  @default_web_args ["--allowedTools", "WebSearch,WebFetch"]

  @impl true
  def complete(%Request{} = req, opts) do
    opts = Keyword.put_new(opts, :executable, "claude")

    args =
      ["-p", "--output-format", "json"] ++
        CLI.model_args(req.model || opts[:model], "--model") ++
        if(req.allow_web, do: opts[:web_args] || @default_web_args, else: [])

    with {:ok, out} <- CLI.run(req, opts, args),
         {:ok, data} <- CLI.decode_json(out) do
      parse(data)
    end
  end

  @doc false
  def parse(%{"is_error" => true} = data),
    do: {:error, {:claude_error, data["result"] || data["subtype"] || "unknown error"}}

  def parse(%{"result" => text} = data) when is_binary(text) do
    usage = data["usage"] || %{}

    {:ok,
     %Response{
       text: text,
       tokens_in: sum_input(usage),
       tokens_out: usage["output_tokens"],
       cost_usd: data["total_cost_usd"],
       model: data["modelUsage"] |> model_name(),
       raw: data
     }}
  end

  def parse(data), do: {:error, {:unexpected_claude_output, data}}

  defp sum_input(usage) do
    ~w(input_tokens cache_read_input_tokens cache_creation_input_tokens)
    |> Enum.map(&(usage[&1] || 0))
    |> Enum.sum()
    |> case do
      0 -> nil
      n -> n
    end
  end

  defp model_name(%{} = usage) when map_size(usage) > 0, do: usage |> Map.keys() |> hd()
  defp model_name(_), do: nil

  @impl true
  def check(opts) do
    CLI.check(
      Keyword.put_new(opts, :executable, "claude"),
      "uses your Claude subscription (run `claude` once to log in)"
    )
  end
end
