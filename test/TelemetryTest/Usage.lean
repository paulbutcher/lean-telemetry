/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Telemetry
import Telemetry.Sdk
import Telemetry.Testing
import TelemetryTest.Harness

/-! The examples the README gives, so that they cannot rot unnoticed. -/

namespace TelemetryTest.Usage

open Telemetry Telemetry.Testing

def solve : TelemetryT IO Unit :=
  spanning "solve" (attrs := [("solver.strategy", "greedy")]) do
    info "starting" [("attempt", 1)]
    span "score" fun s => do
      s.add [("score.total", 42)]

def main : IO Unit := do
  Sdk.installFromEnv
  try
    runTelemetry solve
  finally
    Sdk.shutdown

def solveIsInstrumented : IO Bool := do
  let (_, captured) ← capture (runTelemetry solve)
  return captured.spans.map (·.name) == #["score", "solve"]
    && captured.logs.map (·.body) == #["starting"]

def suite : TestM Unit := do
  check "the capture the README shows holds" (← solveIsInstrumented)

end TelemetryTest.Usage
