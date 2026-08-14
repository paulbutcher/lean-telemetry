/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Std.Sync.Mutex
import Telemetry.Sdk.Exporter
import Telemetry.Sdk.Otlp

/-!
Segment files are only ever created, appended to and deleted. Nothing is renamed or truncated,
so a reader holding a file open keeps reading the same file, and rotation is nothing more than
opening the next one.
-/

namespace Telemetry.Sdk.File

structure Config where
  directory : System.FilePath
  maxBytes : Nat
  maxSegments : Nat
  deriving Repr

def defaultMaxBytes : Nat := 8 * 1024 * 1024

def defaultMaxSegments : Nat := 8

private def prefix_ : String := "telemetry-"

private def suffix : String := ".jsonl"

def segmentName (number : Nat) : String :=
  let digits := toString number
  let padding := if digits.length ≥ 6 then "" else "".pushn '0' (6 - digits.length)
  s!"{prefix_}{padding}{digits}{suffix}"

def segmentNumber? (name : String) : Option Nat :=
  if name.startsWith prefix_ && name.endsWith suffix && name.length > prefix_.length + suffix.length then
    (name.drop prefix_.length |>.dropEnd suffix.length).toString.toNat?
  else
    none

/-- Numbering only ever increases, so a restart continues above whatever is already there. -/
def nextNumber (existing : Array Nat) : Nat :=
  existing.foldl (fun best number => max best (number + 1)) 0

/-- The segments to delete once `maxSegments` is exceeded, lowest-numbered first. -/
def surplus (existing : Array Nat) (maxSegments : Nat) : Array Nat :=
  let keep := max maxSegments 1
  let sorted := existing.qsort (· < ·)
  if sorted.size ≤ keep then #[] else sorted.extract 0 (sorted.size - keep)

private structure Segment where
  handle : IO.FS.Handle
  number : Nat
  written : Nat

private def segmentNumbers (directory : System.FilePath) : IO (Array Nat) := do
  let entries ← directory.readDir
  return entries.filterMap fun entry => segmentNumber? entry.fileName

private def openSegment (directory : System.FilePath) (number : Nat) : IO IO.FS.Handle :=
  IO.FS.Handle.mk (directory / segmentName number) .append

private def prune (config : Config) : IO Unit := do
  for number in surplus (← segmentNumbers config.directory) config.maxSegments do
    IO.FS.removeFile (config.directory / segmentName number)

private def writeLine (config : Config) (segment : Std.Mutex Segment) (line : String) :
    IO Unit :=
  segment.atomically do
    let current ← get
    let current ←
      if current.written ≥ config.maxBytes then
        let number := current.number + 1
        let handle ← openSegment config.directory number
        prune config
        pure { handle, number, written := 0 }
      else
        pure current
    current.handle.putStr line
    current.handle.flush
    set { current with written := current.written + line.utf8ByteSize }

/--
Fails rather than starting without the directory it was asked for: a silently disabled exporter
is indistinguishable from one whose output is not arriving.
-/
def otlpJson (resource : Resource) (config : Config) : IO Exporter := do
  IO.FS.createDirAll config.directory
  let number := nextNumber (← segmentNumbers config.directory)
  let segment ← Std.Mutex.new
    { handle := ← openSegment config.directory number, number, written := 0 }
  return {
    exportSpans := fun spans => writeLine config segment (Otlp.traceRequest resource spans ++ "\n")
    exportLogs := fun records => writeLine config segment (Otlp.logsRequest resource records ++ "\n")
    shutdown := segment.atomically do (← get).handle.flush
  }

end Telemetry.Sdk.File
