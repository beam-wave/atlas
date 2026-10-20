defmodule Atlas.LLM.Adapters.AnthropicAPI do
  @moduledoc """
  Claude Messages API over HTTP (Req), for hosted deployments where no
  subscription CLI is logged in. Needs `ANTHROPIC_API_KEY` (or `:api_key`).

  Config keys: `:api_key`, `:model` (default `"claude-opus-5-5"`),
  `:max_tokens` (default 16_000), `:effort` (`"low"`..`"max"`, optional),
  `:fallbacks` (default true: server-side refusal fallback), `:base_url`,
  `:timeout`, `:req_options` (merged into `Req.new/1`; tests pass a plug).
  """
  @behaviour Atlas.LLM.Adapter

  alias Atlas.LLM.{Request, Response}

  @default_model "claude-opus-5-5"
  @version "2023-06-01"
  @fallback_beta "server-side-fallback-2026-07-01"
  @max_continuations 3

  @impl true
  def complete(%Request{} = req, opts) do
    with {:ok, key} <- api_key(opts) do
      model = req.model || opts[:model] || @default_model
      body = body(req, model, opts)
      client = client(key, req, opts)
      loop(client, body, 0, %{tokens_in: 0, tokens_out: 0})
    end
  end

  defp body(req, model, opts) do
    %{
      "model" => model,
      "max_tokens" => opts[:max_tokens] || 16_000,
      "messages" => [%{"role" => "user", "content" => req.prompt}]
    }
    |> put_if(req.system not in [nil, ""], "system", req.system)
    |> put_if(opts[:effort] != nil, "output_config", %{"effort" => opts[:effort]})
    |> put_if(Keyword.get(opts, :fallbacks, true), "fallbacks", "default")
    |> put_if(req.allow_web, "tools", [
      %{"type" => "web_search_20260209", "name" => "web_search", "max_uses" => 5}
    ])
  end

  defp client(key, req, opts) do
    headers =
      [{"x-api-key", key}, {"anthropic-version", @version}] ++
        if(Keyword.get(opts, :fallbacks, true),
          do: [{"anthropic-beta", @fallback_beta}],
          else: []
        )

    Req.new(
      [
        base_url: opts[:base_url] || "https://api.anthropic.com",
        url: "/v1/messages",
        method: :post,
        headers: headers,
        receive_timeout: req.timeout || opts[:timeout] || 600_000,
        retry: :transient,
        max_retries: 2
      ]
      |> Keyword.merge(opts[:req_options] || [])
    )
  end

  # A server tool (web search) can pause a long turn; resend to let it finish.
  defp loop(client, body, n, usage) do
    case Req.request(client, json: body) do
      {:ok, %Req.Response{status: 200, body: %{} = resp}} ->
        usage = add_usage(usage, resp["usage"])

        case resp["stop_reason"] do
          "refusal" ->
            {:error, {:refusal, get_in(resp, ["stop_details", "category"])}}

          "pause_turn" when n < @max_continuations ->
            messages =
              body["messages"] ++ [%{"role" => "assistant", "content" => resp["content"]}]

            loop(client, %{body | "messages" => messages}, n + 1, usage)

          _ ->
            {:ok,
             %Response{
               text: text(resp["content"]),
               tokens_in: usage.tokens_in,
               tokens_out: usage.tokens_out,
               cost_usd: nil,
               model: resp["model"],
               raw: resp
             }}
        end

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:http_error, status, error_message(body)}}

      {:error, exception} ->
        {:error, {:transport_error, Exception.message(exception)}}
    end
  end

  defp text(content) when is_list(content) do
    content
    |> Enum.filter(&(&1["type"] == "text"))
    |> Enum.map_join("", & &1["text"])
  end

  defp text(_), do: ""

  defp add_usage(acc, nil), do: acc

  defp add_usage(acc, u) do
    %{
      tokens_in: acc.tokens_in + (u["input_tokens"] || 0) + (u["cache_read_input_tokens"] || 0),
      tokens_out: acc.tokens_out + (u["output_tokens"] || 0)
    }
  end

  defp error_message(%{"error" => %{"message" => m}}), do: m
  defp error_message(body), do: inspect(body) |> String.slice(0, 500)

  defp api_key(opts) do
    case opts[:api_key] || System.get_env("ANTHROPIC_API_KEY") do
      key when is_binary(key) and key != "" -> {:ok, key}
      _ -> {:error, :missing_api_key}
    end
  end

  defp put_if(map, true, k, v), do: Map.put(map, k, v)
  defp put_if(map, _, _k, _v), do: map

  @impl true
  def check(opts) do
    case api_key(opts) do
      {:ok, _} -> {:ok, "ANTHROPIC_API_KEY is set (model #{opts[:model] || @default_model})"}
      {:error, _} -> {:error, "ANTHROPIC_API_KEY is not set"}
    end
  end
end
