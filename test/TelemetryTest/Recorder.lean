/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
module

public import Telemetry.Hooks

public section

namespace TelemetryTest

open Telemetry

structure SpanSnapshot where
  ctx : SpanContext
  parentSpanId : Option String
  kind : SpanKind
  name : String
  attrs : Attrs
  status : StatusCode
  statusMessage : Option String
  startUnixNano : Nat
  endUnixNano : Nat
  deriving Repr, BEq

structure Recorder where
  spans : IO.Ref (Array SpanSnapshot)
  logs : IO.Ref (Array LogRecord)

def Recorder.new : IO Recorder :=
  return { spans := ← IO.mkRef #[], logs := ← IO.mkRef #[] }

def Recorder.hooks (recorder : Recorder) : Hooks where
  reportSpan span startUnixNano endUnixNano := do
    let name ← span.name.get
    let attrs ← span.attrs.get
    let (status, statusMessage) ← span.status.get
    recorder.spans.modify (·.push {
      ctx := span.ctx
      parentSpanId := span.parentSpanId
      kind := span.kind
      name, attrs, status, statusMessage, startUnixNano, endUnixNano })
  emitLog record := recorder.logs.modify (·.push record)

/-- Runs `act` with a recorder standing in for the SDK, leaving no hooks installed after. -/
def withRecorder (act : Recorder → IO α) : IO α := do
  let recorder ← Recorder.new
  installHooks recorder.hooks
  try
    act recorder
  finally
    clearHooks

end TelemetryTest
