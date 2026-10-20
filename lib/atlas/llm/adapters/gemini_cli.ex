defmodule Atlas.LLM.Adapters.GeminiCLI do
  @moduledoc """
  Google's Gemini CLI (`gemini -p`), using the user's Google login or
  Gemini plan.

  Config keys: `:executable` (default `"gemini"`), `:model`, `:timeout`,
  `:extra_args`, `:env`.
  """
  @behaviour Atlas.LLM.Adapter

  alias Atlas.LLM.Adapters.CLI
  alias Atlas.LLM.{Request, Response}

  @impl true
  def complete(%Request{} = req, opts) do
    opts = Keyword.put_new(opts, :executable, "gemini")

    # gemini appends the `-p` text to whatever arrives on stdin.
    args =
      ["--output-format", "json"] ++
        CLI.model_args(req.model || opts[:model], "--model") ++
        ["-p", "Carry out the task above."]

    with {:ok, out} <- CLI.run(req, opts, args),
         {:ok, data} <- CLI.decode_json(out) do
      parse(data)
    end
  end

  @doc false
  def parse(%{"error" => %{"message" => m}}) when is_binary(m), do: {:error, {:gemini_error, m}}

  def parse(%{"response" => text} = data) when is_binary(text) do
    {model, tokens} =
      case get_in(data, ["stats", "models"]) do
        %{} = models when map_size(models) > 0 ->
          {name, stats} = Enum.at(models, 0)
          {name, stats["tokens"] || %{}}

        _ ->
          {nil, %{}}
      end

    {:ok,
     %Response{
       text: text,
       tokens_in: tokens["prompt"],
       tokens_out: tokens["candidates"],
       model: model,
       raw: data
     }}
  end

  def parse(data), do: {:error, {:unexpected_gemini_output, data}}

  @impl true
  def check(opts) do
    CLI.check(
      Keyword.put_new(opts, :executable, "gemini"),
      "uses your Google account (run `gemini` once to log in)"
    )
  end
end
