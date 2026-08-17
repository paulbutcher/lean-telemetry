/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Telemetry.Testing
import TelemetryTest.Harness

namespace TelemetryTest.Testing

open Telemetry Telemetry.Testing

private structure Displaced where
  captured : Captured
  outerSpans : Array String
  outerShutdowns : Nat

private def displacing : IO Displaced := do
  let outer ← Recorder.new
  Sdk.install { attrs := [] } #[outer.exporter]
  try
    let (_, captured) ← capture do
      runTelemetry do
        spanning "inside" (attrs := [("k", "v")]) do
          info "logged inside"
    runTelemetry (spanning "after" (pure ()))
    return {
      captured
      outerSpans := (← outer.spans.get).map (·.name)
      outerShutdowns := ← outer.shutdowns.get
    }
  finally
    Sdk.shutdown

private def afterException : IO (Bool × Array String) := do
  let outer ← Recorder.new
  Sdk.install { attrs := [] } #[outer.exporter]
  try
    let threw ←
      try
        let _ ← capture (α := Unit) (throw (IO.userError "boom"))
        pure false
      catch _ =>
        pure true
    runTelemetry (spanning "after the exception" (pure ()))
    return (threw, (← outer.spans.get).map (·.name))
  finally
    Sdk.shutdown

private def fromClean : IO (Nat × Option SpanContext) := do
  Sdk.shutdown
  let (_, captured) ← capture (runTelemetry (spanning "inside" (pure ())))
  let ctx ← runTelemetry <| span "after" fun (s : Span) => pure s.context
  return (captured.spans.size, ctx)

def suite : TestM Unit := do
  let displaced ← displacing
  checkEq "what the action emits reaches the recorder"
    (displaced.captured.spans.map (·.name)) #["inside"]
  checkEq "log records included" (displaced.captured.logs.map (·.body)) #["logged inside"]
  checkEq "with their attributes"
    (displaced.captured.spans.map (·.attrs)) #[[("k", Value.str "v")]]
  check "the record is tied to the span it was emitted in"
    (displaced.captured.logs.any fun record =>
      displaced.captured.spans.any fun span => record.ctx.any (·.spanId == span.ctx.spanId))
  checkEq "a displaced installation is in place again, and saw nothing of the capture"
    displaced.outerSpans #["after"]
  checkEq "restoring does not shut a displaced installation down" displaced.outerShutdowns 0
  checkEq "nor is the recorder shut down for the test" displaced.captured.shutdowns 0

  let (threw, afterwards) ← afterException
  check "an exception from the action propagates" threw
  checkEq "and what was displaced is restored even so" afterwards #["after the exception"]

  let (inside, ctx) ← fromClean
  checkEq "capturing with nothing installed beforehand still records" inside 1
  checkEq "and leaves nothing installed afterwards" ctx none

end TelemetryTest.Testing
