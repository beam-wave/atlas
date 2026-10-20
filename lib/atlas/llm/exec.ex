defmodule Atlas.LLM.Exec do
  @moduledoc """
  Runs a CLI with a prompt on stdin, captures stdout and stderr separately,
  and kills the OS process on timeout.

  The prompt goes through a temp file rather than argv: skills make prompts
  large, and Linux caps a single argument at 128 KB.
  """
  require Logger

  @type result :: %{stdout: String.t(), stderr: String.t(), status: integer()}

  @doc """
  Options: `:stdin` (string fed on stdin), `:timeout` (ms, default 300_000),
  `:env` (list of `{name, value}` strings), `:cd` (working directory).
  """
  @spec run(String.t(), [String.t()], keyword()) :: {:ok, result()} | {:error, term()}
  def run(executable, args, opts \\ []) do
    with {:ok, path} <- resolve(executable) do
      tmp = Path.join(System.tmp_dir!(), "atlas-exec-#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp)
      stdin_file = Path.join(tmp, "stdin")
      stderr_file = Path.join(tmp, "stderr")
      File.write!(stdin_file, opts[:stdin] || "")

      try do
        spawn_and_collect(path, args, stdin_file, stderr_file, opts)
      after
        File.rm_rf(tmp)
      end
    end
  end

  @doc "Finds an executable on PATH, or accepts an existing absolute/relative path."
  def resolve(executable) do
    cond do
      String.contains?(executable, "/") and File.regular?(executable) ->
        {:ok, Path.expand(executable)}

      path = System.find_executable(executable) ->
        {:ok, path}

      true ->
        {:error, {:executable_not_found, executable}}
    end
  end

  defp spawn_and_collect(path, args, stdin_file, stderr_file, opts) do
    timeout = opts[:timeout] || 300_000
    sh = System.find_executable("sh")
    script = ~s(exec "$0" "$@" < "$ATLAS_STDIN" 2> "$ATLAS_STDERR")

    env =
      [{"ATLAS_STDIN", stdin_file}, {"ATLAS_STDERR", stderr_file} | opts[:env] || []]
      |> Enum.map(fn {k, v} ->
        {String.to_charlist(k), if(v, do: String.to_charlist(v), else: false)}
      end)

    port_opts =
      [:binary, :exit_status, :use_stdio, :hide, args: ["-c", script, path | args], env: env] ++
        if(cd = opts[:cd], do: [cd: String.to_charlist(cd)], else: [])

    port = Port.open({:spawn_executable, sh}, port_opts)
    deadline = System.monotonic_time(:millisecond) + timeout

    case collect(port, [], deadline) do
      {:ok, stdout, status} ->
        {:ok, %{stdout: stdout, stderr: read_stderr(stderr_file), status: status}}

      {:error, :timeout} ->
        kill(port)
        {:error, {:timeout, timeout, read_stderr(stderr_file)}}
    end
  end

  defp collect(port, acc, deadline) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {^port, {:data, data}} -> collect(port, [acc | data], deadline)
      {^port, {:exit_status, status}} -> {:ok, IO.iodata_to_binary(acc), status}
    after
      remaining -> {:error, :timeout}
    end
  end

  defp kill(port) do
    case Port.info(port, :os_pid) do
      {:os_pid, pid} ->
        System.cmd("kill", ["-TERM", Integer.to_string(pid)], stderr_to_stdout: true)
        Process.sleep(200)
        System.cmd("kill", ["-KILL", Integer.to_string(pid)], stderr_to_stdout: true)

      nil ->
        :ok
    end

    try do
      Port.close(port)
    rescue
      ArgumentError -> :ok
    end

    flush(port)
  end

  defp flush(port) do
    receive do
      {^port, _} -> flush(port)
    after
      0 -> :ok
    end
  end

  defp read_stderr(file) do
    case File.read(file) do
      {:ok, body} -> String.slice(body, 0, 4000)
      _ -> ""
    end
  end
end
