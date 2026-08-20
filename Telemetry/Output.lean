/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
module

public import Std.Sync.Mutex

public section

namespace Telemetry.Output

/--
Concurrent writers share these streams, and POSIX only guarantees atomicity below `PIPE_BUF`,
which a span line will exceed. Everything writing to a stream holds the stream's lock for the
whole of its write, and issues one write call per line.
-/
initialize stdoutLock : Std.BaseMutex ← Std.BaseMutex.new

initialize stderrLock : Std.BaseMutex ← Std.BaseMutex.new

private def write (lock : Std.BaseMutex) (stream : IO.FS.Stream) (line : String) : IO Unit := do
  lock.lock
  try
    stream.putStr line
    stream.flush
  finally
    lock.unlock

def stdout (line : String) : IO Unit := do
  write stdoutLock (← IO.getStdout) line

def stderr (line : String) : IO Unit := do
  write stderrLock (← IO.getStderr) line

/-- Sends a line to stderr when `isError`, and to stdout otherwise. -/
def line (isError : Bool) (line : String) : IO Unit :=
  if isError then Output.stderr line else Output.stdout line

end Telemetry.Output
