/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Telemetry.Monad
import TelemetryTest.Harness

namespace TelemetryTest.Monad

open Telemetry

def ctxA : SpanContext := { traceId := "a", spanId := "1" }
def ctxB : SpanContext := { traceId := "b", spanId := "2" }

/-- The stacks the class has to survive, each reporting what it sees at three nesting levels. -/
private def observe [Monad m] [MonadTelemetry m] : m (List (Option SpanContext)) := do
  let outer ← currentSpan
  let (inner, restored) ← withSpanContext (some ctxA) do
    let inner ← currentSpan
    let nested ← withSpanContext (some ctxB) currentSpan
    return (inner, nested)
  return [outer, inner, restored]

def suite : TestM Unit := do
  checkEq "TelemetryT IO" (← runTelemetry observe) [none, some ctxA, some ctxB]
  checkEq "ReaderT over TelemetryT"
    (← runTelemetry (ReaderT.run (ρ := Nat) observe 0)) [none, some ctxA, some ctxB]
  checkEq "StateT over TelemetryT"
    (← runTelemetry (StateT.run' (σ := Nat) observe 0)) [none, some ctxA, some ctxB]
  checkEq "ExceptT over TelemetryT"
    (← runTelemetry (ExceptT.run (ε := String) observe)).toOption
    (some [none, some ctxA, some ctxB])
  -- The case the plan warns about: an inner reader makes bare `read` ambiguous.
  checkEq "TelemetryT over ReaderT"
    (← ReaderT.run (ρ := Nat) (runTelemetry observe) 0) [none, some ctxA, some ctxB]
  checkEq "context is restored after the scope"
    (← runTelemetry (withSpanContext (some ctxA) (pure ()) *> currentSpan)) none

end TelemetryTest.Monad
