defmodule Atlas.LLM.Adapters.CLI do
  @moduledoc """
  Shared plumbing for subscription CLIs (Claude Code, Codex, Cursor, Gemini).

  Each CLI runs in an empty scratch directory so it cannot read or edit the
  user's files, with the full prompt on stdin.
  """
  alias Atlas.LLM.{Exec, Request}

  @doc """
  Runs `executable args` with the request's prompt on stdin and returns stdout
  when the exit status is 0.
  """
  def run(%Request{} = req, opts, args) do
    exe = Keyword.fetch!(opts, :executable)

    exec_opts = [
      stdin: Request.combined(req),
      timeout: req.timeout || opts[:timeout] || 300_000,
      env: opts[:env] || [],
      cd: scratch_dir()
    ]

    case Exec.run(exe, args ++ (opts[:extra_args] || []), exec_opts) do
      {:ok, %{status: 0, stdout: out}} ->
        {:ok, out}

      {:ok, %{status: status, stdout: out, stderr: err}} ->
        {:error, {:exit_status, status, String.slice(String.trim(err <> "\n" <> out), 0, 2000)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Checks that the executable exists and answers `--version`."
  def check(opts, login_hint) do
    exe = Keyword.fetch!(opts, :executable)

    case Exec.run(exe, ["--version"], timeout: 15_000) do
      {:ok, %{status: 0, stdout: out}} ->
        {:ok, "#{exe} #{out |> String.trim() |> String.split("\n") |> hd()} — #{login_hint}"}

      {:ok, %{status: status, stderr: err}} ->
        {:error, "#{exe} --version exited #{status}: #{String.trim(err)}"}

      {:error, {:executable_not_found, _}} ->
        {:error, "#{exe} not found on PATH"}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  def model_args(nil, _flag), do: []
  def model_args("", _flag), do: []
  def model_args(model, flag), do: [flag, model]

  def decode_json(text) do
    case Jason.decode(String.trim(text)) do
      {:ok, data} -> {:ok, data}
      {:error, _} -> {:error, {:unparseable_cli_output, String.slice(text, 0, 500)}}
    end
  end

  defp scratch_dir do
    dir = Path.join(System.tmp_dir!(), "atlas-llm-scratch")
    File.mkdir_p!(dir)
    dir
  end
end
