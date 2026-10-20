defmodule Atlas.LLM.ExecTest do
  use ExUnit.Case, async: true

  alias Atlas.LLM.Exec

  import Atlas.Fixtures, only: [tmp_file: 2]

  defp script(body) do
    path = tmp_file("fake", "#!/bin/sh\n" <> body)
    File.chmod!(path, 0o755)
    path
  end

  test "feeds stdin, passes args, separates stdout and stderr" do
    exe = script(~s(echo "args:$*"; cat; echo "oops" >&2))

    assert {:ok, %{stdout: out, stderr: err, status: 0}} =
             Exec.run(exe, ["-p", "two words"], stdin: "hello\nworld")

    assert out == "args:-p two words\nhello\nworld"
    assert err == "oops\n"
  end

  test "handles large prompts via stdin" do
    exe = script("wc -c")
    big = String.duplicate("x", 300_000)
    assert {:ok, %{stdout: out}} = Exec.run(exe, [], stdin: big)
    assert String.trim(out) == "300000"
  end

  test "reports non-zero exit status" do
    exe = script("echo fail >&2; exit 3")
    assert {:ok, %{status: 3, stderr: "fail\n"}} = Exec.run(exe, [])
  end

  test "passes env and working directory" do
    exe = script(~s(echo "$FOO"; pwd))
    dir = System.tmp_dir!() |> Path.join("atlas-exec-cd-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    assert {:ok, %{stdout: out}} = Exec.run(exe, [], env: [{"FOO", "bar"}], cd: dir)
    [foo, pwd] = String.split(out, "\n", trim: true)
    assert foo == "bar"
    assert Path.basename(pwd) == Path.basename(dir)
  end

  test "kills the process on timeout" do
    exe = script("echo started; sleep 30")
    started = System.monotonic_time(:millisecond)
    assert {:error, {:timeout, 300, _}} = Exec.run(exe, [], timeout: 300)
    assert System.monotonic_time(:millisecond) - started < 5_000
  end

  test "reports a missing executable" do
    assert {:error, {:executable_not_found, "definitely-not-a-real-cli-xyz"}} =
             Exec.run("definitely-not-a-real-cli-xyz", [])
  end

  test "resolves executables on PATH" do
    assert {:ok, path} = Exec.resolve("sh")
    assert File.exists?(path)
  end
end
