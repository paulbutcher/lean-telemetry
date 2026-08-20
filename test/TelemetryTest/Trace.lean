/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
module

public import Telemetry.Trace
public import TelemetryTest.Harness
public import TelemetryTest.Recorder

public section

namespace TelemetryTest.Trace

open Telemetry

private def nested : IO (Array SpanSnapshot) :=
  withRecorder fun recorder => do
    runTelemetry do
      spanning "outer" (attrs := [("attempt", 1)]) do
        spanning "inner" (kind := .client) (pure ())
    recorder.spans.get

private def failing : IO (Bool × Array SpanSnapshot) :=
  withRecorder fun recorder => do
    let threw ←
      try
        runTelemetry (spanning "boom" (throw (IO.userError "kaboom")))
        pure false
      catch _ =>
        pure true
    return (threw, ← recorder.spans.get)

private def withoutSdk : IO (Option SpanContext × Nat) := do
  clearHooks
  let recorder ← Recorder.new
  let ctx ← runTelemetry <| span "ignored" fun (s : Span) => do
    s.add [("k", "v")]
    s.rename "renamed"
    s.setStatus .error (some "unheard")
    return s.context
  return (ctx, (← recorder.spans.get).size)

def suite : TestM Unit := do
  let spans ← nested
  checkEq "a parent and its child are both reported" spans.size 2
  if h : spans.size = 2 then
    let inner := spans[0]'(by omega)
    let outer := spans[1]'(by omega)
    checkEq "children are reported first" (inner.name, outer.name) ("inner", "outer")
    checkEq "the child points at its parent" inner.parentSpanId (some outer.ctx.spanId)
    checkEq "the child shares the trace" inner.ctx.traceId outer.ctx.traceId
    check "the child has its own span id" (inner.ctx.spanId != outer.ctx.spanId)
    checkEq "a root has no parent" outer.parentSpanId none
    checkEq "the kind is carried through" inner.kind SpanKind.client
    checkEq "the default kind is internal" outer.kind SpanKind.internal
    checkEq "attributes given at the call site are kept" outer.attrs [("attempt", (1 : Value))]
    checkEq "an uneventful span is left unset" outer.status StatusCode.unset
    check "the span ends no earlier than it starts" (outer.endUnixNano ≥ outer.startUnixNano)
    check "the span covers its child" (outer.startUnixNano ≤ inner.startUnixNano)
  else
    pure ()

  let (threw, failures) ← failing
  check "the exception is re-raised" threw
  checkEq "a failed span is still reported" failures.size 1
  if h : failures.size = 1 then
    let failed := failures[0]'(by omega)
    checkEq "a failed span is marked as an error" failed.status StatusCode.error
    check "the exception message becomes the status message"
      (failed.statusMessage.any (containsText · "kaboom"))
  else
    pure ()

  let (ctx, reported) ← withoutSdk
  checkEq "with no SDK the span is inert" ctx none
  checkEq "with no SDK nothing is reported" reported 0

end TelemetryTest.Trace
