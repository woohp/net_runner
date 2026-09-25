defmodule NetRunner.StderrExitRaceTest do
  # Not async: the concurrent spawns would starve timing-sensitive tests such as
  # IOPipeliningTest's read sizing.
  use ExUnit.Case, async: false

  alias NetRunner.Process, as: Proc

  # The exit status can arrive over the UDS before the select-driven stderr
  # drain has read the child's last write. Once await_exit/1 returns, the tail
  # must already hold everything the child wrote. The race is rare (about 1 in
  # 2,000 on an ubuntu-latest runner), hence the many concurrent runs.
  test "the stderr tail is complete as soon as await_exit returns" do
    tails =
      1..2_000
      |> Task.async_stream(
        fn _ ->
          {:ok, pid} = Proc.start("sh", ["-c", "printf diagnostic >&2; exit 7"])
          {:ok, 7} = Proc.await_exit(pid)
          Proc.stderr_tail(pid)
        end,
        max_concurrency: 64,
        timeout: :infinity
      )
      |> Enum.map(fn {:ok, tail} -> tail end)

    assert Enum.reject(tails, &(&1 == "diagnostic")) == []
  end

  test "run/2 with stderr: :capture returns the complete tail" do
    results =
      1..2_000
      |> Task.async_stream(
        fn _ ->
          NetRunner.run(["sh", "-c", "printf diagnostic >&2; exit 7"], stderr: :capture)
        end,
        max_concurrency: 64,
        timeout: :infinity
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.reject(results, &(&1 == {"", 7, "diagnostic"})) == []
  end
end
