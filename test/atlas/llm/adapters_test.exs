defmodule Atlas.LLM.AdaptersTest do
  @moduledoc """
  Each subscription CLI adapter is exercised against a fake executable that
  records its arguments and stdin and prints what the real CLI prints.
  """
  use ExUnit.Case, async: true

  import Atlas.Fixtures, only: [tmp_file: 2]

  alias Atlas.LLM.Adapters.{AnthropicAPI, ClaudeCLI, CodexCLI, CursorCLI, GeminiCLI}
  alias Atlas.LLM.{Request, Response}

  # A fake CLI: writes "$@" and stdin to log files next to itself, then prints `output`.
  defp fake_cli(output, exit_code \\ 0) do
    out_file = tmp_file("output", output)
    dir = Path.dirname(out_file)

    exe =
      tmp_file("cli", """
      #!/bin/sh
      printf '%s\\n' "$@" > "#{dir}/args"
      cat > "#{dir}/stdin"
      pwd > "#{dir}/cwd"
      cat "#{out_file}"
      exit #{exit_code}
      """)

    File.chmod!(exe, 0o755)
    {exe, dir}
  end

  defp args(dir), do: dir |> Path.join("args") |> File.read!() |> String.split("\n", trim: true)
  defp stdin(dir), do: File.read!(Path.join(dir, "stdin"))

  @req %Request{system: "SYSTEM", prompt: "TASK", agent: "intake"}

  describe "ClaudeCLI" do
    @claude_ok ~s({"type":"result","subtype":"success","is_error":false,"result":"{\\"ok\\":true}","total_cost_usd":0.012,"usage":{"input_tokens":10,"cache_read_input_tokens":90,"output_tokens":7},"modelUsage":{"claude-opus-5-5":{}}})

    test "runs claude -p with JSON output and the prompt on stdin" do
      {exe, dir} = fake_cli(@claude_ok)
      assert {:ok, %Response{} = r} = ClaudeCLI.complete(@req, executable: exe)
      assert r.text == ~s({"ok":true})
      assert r.tokens_in == 100
      assert r.tokens_out == 7
      assert r.cost_usd == 0.012
      assert r.model == "claude-opus-5-5"
      assert args(dir) == ["-p", "--output-format", "json"]
      assert stdin(dir) == "SYSTEM\n\n=== TASK ===\n\nTASK"
      # Runs in a scratch directory, never the project.
      refute File.read!(Path.join(dir, "cwd")) =~ File.cwd!()
    end

    test "adds model and web tools when asked" do
      {exe, dir} = fake_cli(@claude_ok)

      {:ok, _} =
        ClaudeCLI.complete(%{@req | allow_web: true, model: "claude-sonnet-5-5"}, executable: exe)

      assert args(dir) == [
               "-p",
               "--output-format",
               "json",
               "--model",
               "claude-sonnet-5-5",
               "--allowedTools",
               "WebSearch,WebFetch"
             ]
    end

    test "surfaces CLI errors" do
      {exe, _} = fake_cli(~s({"type":"result","is_error":true,"result":"Not logged in"}))

      assert {:error, {:claude_error, "Not logged in"}} =
               ClaudeCLI.complete(@req, executable: exe)

      {exe, _} = fake_cli("boom", 1)
      assert {:error, {:exit_status, 1, "boom"}} = ClaudeCLI.complete(@req, executable: exe)

      {exe, _} = fake_cli("not json")

      assert {:error, {:unparseable_cli_output, "not json"}} =
               ClaudeCLI.complete(@req, executable: exe)

      assert {:error, {:executable_not_found, "no-such-claude"}} =
               ClaudeCLI.complete(@req, executable: "no-such-claude")
    end
  end

  describe "CodexCLI" do
    @codex_jsonl """
    {"type":"thread.started","thread_id":"t1"}
    {"type":"turn.started"}
    {"type":"item.completed","item":{"id":"i0","type":"reasoning","text":"thinking"}}
    {"type":"item.completed","item":{"id":"i1","type":"agent_message","text":"{\\"ok\\":1}"}}
    {"type":"turn.completed","usage":{"input_tokens":120,"cached_input_tokens":0,"output_tokens":9}}
    """

    test "runs codex exec read-only, reading the prompt from stdin" do
      {exe, dir} = fake_cli(@codex_jsonl)
      assert {:ok, r} = CodexCLI.complete(%{@req | model: "gpt-5-codex"}, executable: exe)
      assert r.text == ~s({"ok":1})
      assert r.tokens_in == 120
      assert r.tokens_out == 9

      assert args(dir) == [
               "exec",
               "--json",
               "--skip-git-repo-check",
               "--sandbox",
               "read-only",
               "--model",
               "gpt-5-codex",
               "-"
             ]

      assert stdin(dir) =~ "TASK"
    end

    test "parses the older msg envelope" do
      out =
        ~s({"msg":{"type":"agent_message","message":"hello"}}\n{"msg":{"type":"token_count","input_tokens":5,"output_tokens":2}}\n)

      assert {:ok, %{text: "hello", tokens_in: 5, tokens_out: 2}} = CodexCLI.parse(out)
    end

    test "reports turn failures" do
      out = ~s({"type":"turn.failed","error":{"message":"usage limit reached"}}\n)
      assert {:error, {:codex_error, "usage limit reached"}} = CodexCLI.parse(out)
      assert {:error, {:unexpected_codex_output, _}} = CodexCLI.parse("garbage")
    end

    test "adds configured web args only for web-enabled agents" do
      {exe, dir} = fake_cli(@codex_jsonl)

      {:ok, _} =
        CodexCLI.complete(%{@req | allow_web: true}, executable: exe, web_args: ["--search"])

      assert "--search" in args(dir)
    end
  end

  describe "CursorCLI" do
    test "runs cursor-agent -p with JSON output" do
      {exe, dir} =
        fake_cli(
          ~s({"type":"result","subtype":"success","is_error":false,"duration_ms":900,"result":"{}","session_id":"s"})
        )

      assert {:ok, %{text: "{}"}} =
               CursorCLI.complete(%{@req | model: "sonnet-4"}, executable: exe)

      assert args(dir) == ["-p", "--output-format", "json", "--model", "sonnet-4"]
      assert stdin(dir) =~ "SYSTEM"
    end

    test "surfaces errors" do
      {exe, _} =
        fake_cli(~s({"type":"result","is_error":true,"result":"Authentication required"}))

      assert {:error, {:cursor_error, "Authentication required"}} =
               CursorCLI.complete(@req, executable: exe)
    end
  end

  describe "GeminiCLI" do
    test "runs gemini with JSON output and parses token stats" do
      out =
        ~s({"response":"{}","stats":{"models":{"gemini-2.5-pro":{"tokens":{"prompt":50,"candidates":4,"total":54}}}}})

      {exe, dir} = fake_cli(out)

      assert {:ok, %{text: "{}", tokens_in: 50, tokens_out: 4, model: "gemini-2.5-pro"}} =
               GeminiCLI.complete(@req, executable: exe)

      assert ["--output-format", "json", "-p", _] = args(dir)
      assert stdin(dir) =~ "TASK"
    end

    test "surfaces errors" do
      assert {:error, {:gemini_error, "quota"}} =
               GeminiCLI.parse(%{"error" => %{"message" => "quota"}})
    end
  end

  describe "check/1" do
    test "reports a working CLI and a missing one" do
      {exe, _} = fake_cli("9.9.9 (Fake)")
      assert {:ok, msg} = ClaudeCLI.check(executable: exe)
      assert msg =~ "9.9.9"
      assert {:error, msg} = CursorCLI.check(executable: "no-such-cursor")
      assert msg =~ "not found"
    end
  end

  describe "AnthropicAPI" do
    @opts [api_key: "k", req_options: [plug: {Req.Test, __MODULE__}, retry: false]]

    test "posts a Messages request with system prompt, default model and fallbacks" do
      Req.Test.stub(__MODULE__, fn conn ->
        assert conn.request_path == "/v1/messages"
        assert Plug.Conn.get_req_header(conn, "x-api-key") == ["k"]
        assert Plug.Conn.get_req_header(conn, "anthropic-version") == ["2023-06-01"]

        assert Plug.Conn.get_req_header(conn, "anthropic-beta") == [
                 "server-side-fallback-2026-07-01"
               ]

        {:ok, body, conn} = Plug.Conn.read_body(conn)
        body = Jason.decode!(body)
        assert body["model"] == "claude-opus-5-5"
        assert body["system"] == "SYSTEM"
        assert body["fallbacks"] == "default"
        assert body["max_tokens"] == 16_000
        assert [%{"role" => "user", "content" => "TASK"}] = body["messages"]
        refute Map.has_key?(body, "tools")

        Req.Test.json(conn, %{
          "model" => "claude-opus-5-5",
          "stop_reason" => "end_turn",
          "content" => [
            %{"type" => "thinking", "thinking" => ""},
            %{"type" => "text", "text" => "{\"a\":1}"}
          ],
          "usage" => %{"input_tokens" => 11, "output_tokens" => 3}
        })
      end)

      assert {:ok, %{text: ~s({"a":1}), tokens_in: 11, tokens_out: 3, model: "claude-opus-5-5"}} =
               AnthropicAPI.complete(@req, @opts)
    end

    test "continues a paused web-search turn" do
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      Req.Test.stub(__MODULE__, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        body = Jason.decode!(body)
        assert [%{"type" => "web_search_20260209"}] = body["tools"]
        n = Agent.get_and_update(counter, &{&1, &1 + 1})

        if n == 0 do
          Req.Test.json(conn, %{
            "stop_reason" => "pause_turn",
            "content" => [%{"type" => "text", "text" => "part "}],
            "usage" => %{"input_tokens" => 5, "output_tokens" => 1}
          })
        else
          assert length(body["messages"]) == 2

          Req.Test.json(conn, %{
            "stop_reason" => "end_turn",
            "content" => [%{"type" => "text", "text" => "done"}],
            "usage" => %{"input_tokens" => 7, "output_tokens" => 2}
          })
        end
      end)

      assert {:ok, %{text: "done", tokens_in: 12, tokens_out: 3}} =
               AnthropicAPI.complete(%{@req | allow_web: true}, @opts)
    end

    test "maps refusals, HTTP errors and missing keys" do
      Req.Test.stub(__MODULE__, fn conn ->
        Req.Test.json(conn, %{
          "stop_reason" => "refusal",
          "stop_details" => %{"category" => "cyber"},
          "content" => []
        })
      end)

      assert {:error, {:refusal, "cyber"}} = AnthropicAPI.complete(@req, @opts)

      Req.Test.stub(__MODULE__, fn conn ->
        conn
        |> Plug.Conn.put_status(429)
        |> Req.Test.json(%{"error" => %{"message" => "rate limited"}})
      end)

      assert {:error, {:http_error, 429, "rate limited"}} = AnthropicAPI.complete(@req, @opts)

      System.delete_env("ANTHROPIC_API_KEY")

      assert {:error, :missing_api_key} =
               AnthropicAPI.complete(@req, Keyword.delete(@opts, :api_key))

      assert {:error, _} = AnthropicAPI.check([])
    end

    test "omits fallbacks and sets effort when configured" do
      Req.Test.stub(__MODULE__, fn conn ->
        assert Plug.Conn.get_req_header(conn, "anthropic-beta") == []
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        body = Jason.decode!(body)
        refute Map.has_key?(body, "fallbacks")
        assert body["output_config"] == %{"effort" => "low"}
        assert body["model"] == "claude-haiku-5-5"

        Req.Test.json(conn, %{
          "stop_reason" => "end_turn",
          "content" => [%{"type" => "text", "text" => "x"}]
        })
      end)

      assert {:ok, %{text: "x"}} =
               AnthropicAPI.complete(
                 @req,
                 @opts ++ [fallbacks: false, effort: "low", model: "claude-haiku-5-5"]
               )
    end
  end
end
