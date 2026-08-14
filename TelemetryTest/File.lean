/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Telemetry.Sdk.File
import TelemetryTest.Harness

namespace TelemetryTest.File

open Telemetry Telemetry.Sdk Telemetry.Sdk.File

private def sampleSpan (name : String) : SpanData where
  ctx := { traceId := "4bf92f3577b34da6a3ce929d0e0e4736", spanId := "00f067aa0ba902b7" }
  parentSpanId := none
  name := name
  kind := .internal
  startUnixNano := 1755172471882000000
  endUnixNano := 1755172471890000000
  attrs := []
  status := .unset
  statusMessage := none

private structure Written where
  segments : Array Nat
  lines : Nat
  whole : Bool
  continued : Array Nat

private def numbersIn (directory : System.FilePath) : IO (Array Nat) := do
  let entries ← directory.readDir
  return (entries.filterMap fun entry => segmentNumber? entry.fileName).qsort (· < ·)

/-- Writes enough to force several rotations, then reopens the directory as a restart would. -/
private def writeMany : IO Written :=
  IO.FS.withTempDir fun directory => do
    let config : File.Config := { directory, maxBytes := 200, maxSegments := 3 }
    let exporter ← File.otlpJson { attrs := [] } config
    for i in [0:10] do
      exporter.exportSpans #[sampleSpan s!"span {i}"]
    exporter.shutdown
    let segments ← numbersIn directory
    let mut lines := 0
    let mut whole := true
    for number in segments do
      let contents ← IO.FS.readFile (directory / segmentName number)
      for line in contents.splitOn "\n" do
        unless line.isEmpty do
          lines := lines + 1
          whole := whole && line.startsWith "{\"resourceSpans\"" && line.endsWith "}"
    let continuation ← File.otlpJson { attrs := [] } config
    continuation.exportSpans #[sampleSpan "after restart"]
    return { segments, lines, whole, continued := ← numbersIn directory }

private theorem le_foldl_max (l : List Nat) (init : Nat) :
    init ≤ l.foldl (fun best number => max best (number + 1)) init := by
  induction l generalizing init with
  | nil => simp
  | cons a t ih => exact Nat.le_trans (Nat.le_max_left init (a + 1)) (ih _)

private theorem lt_foldl_max (l : List Nat) (init n : Nat) (h : n ∈ l) :
    n < l.foldl (fun best number => max best (number + 1)) init := by
  induction l generalizing init with
  | nil => cases h
  | cons a t ih =>
    cases h with
    | head =>
      exact Nat.lt_of_lt_of_le (Nat.lt_succ_self _)
        (Nat.le_trans (Nat.le_max_right init _) (le_foldl_max t _))
    | tail _ h => exact ih _ h

/--
A restart that reused a number would append to a segment a reader has already passed, losing
everything written after it, so this holds for every directory rather than for the ones a
generator happens to produce.
-/
theorem lt_nextNumber (existing : Array Nat) (n : Nat) (h : n ∈ existing) :
    n < nextNumber existing := by
  rw [Telemetry.Sdk.File.nextNumber, ← Array.foldl_toList]
  exact lt_foldl_max existing.toList 0 n (by simpa using h)

def suite : TestM Unit := do
  checkEq "segment names are zero padded" (segmentName 12) "telemetry-000012.jsonl"
  property "a segment name identifies its segment"
    (∀ n : Nat, segmentNumber? (segmentName n) = some n)
  checkEq "other files are not segments" (segmentNumber? "telemetry.jsonl") none
  checkEq "nor are near misses" (segmentNumber? "telemetry-00zz12.jsonl") none

  checkEq "an empty directory starts at zero" (nextNumber #[]) 0
  checkEq "numbering continues above the highest, not the last" (nextNumber #[0, 7, 3]) 8

  checkEq "nothing is deleted below the cap" (surplus #[1, 2] 3) #[]
  checkEq "the lowest numbers are deleted first" (surplus #[4, 1, 3, 2] 2) #[1, 2]
  -- Retention resists proof only because `surplus` sorts with `Array.qsort`, which the
  -- toolchain ships without lemmas, so there is nothing to reason from.
  property "retention leaves the cap standing"
    (∀ (existing : List Nat) (cap : Nat),
      existing.length - (surplus existing.toArray cap).size = min existing.length (max cap 1))

  let written ← writeMany
  checkEq "no more segments are kept than the limit allows" written.segments.size 3
  check "the segments kept are the newest, consecutively numbered"
    (written.segments.back?.any fun latest =>
      written.segments == #[latest - 2, latest - 1, latest])
  check "each retained segment holds whole lines" written.whole
  checkEq "and one line per exported span" written.lines 3
  check "a restart continues above what it found"
    (written.continued.back?.any fun latest => written.segments.back?.all (· < latest))

end TelemetryTest.File
