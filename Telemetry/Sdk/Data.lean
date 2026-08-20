/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
module

public import Telemetry

public section

namespace Telemetry.Sdk

/-- The completed, immutable record of a span, as handed to an exporter. -/
structure SpanData where
  ctx : SpanContext
  parentSpanId : Option String
  name : String
  kind : SpanKind
  startUnixNano : Nat
  endUnixNano : Nat
  attrs : Attrs
  status : StatusCode
  statusMessage : Option String
  deriving Repr, BEq, Inhabited

def SpanData.ofSpan (span : ActiveSpan) (startUnixNano endUnixNano : Nat) : IO SpanData := do
  let (status, statusMessage) ← span.status.get
  return {
    ctx := span.ctx
    parentSpanId := span.parentSpanId
    name := ← span.name.get
    kind := span.kind
    startUnixNano, endUnixNano
    attrs := ← span.attrs.get
    status, statusMessage
  }

def SpanData.durationNanos (span : SpanData) : Nat :=
  span.endUnixNano - span.startUnixNano

end Telemetry.Sdk
