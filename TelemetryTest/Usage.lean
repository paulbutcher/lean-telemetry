/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Telemetry
import Telemetry.Sdk

/-! The example the README gives, so that it cannot rot unnoticed. -/

namespace TelemetryTest.Usage

open Telemetry

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

end TelemetryTest.Usage
