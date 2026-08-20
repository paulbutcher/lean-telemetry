/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
module

import Plausible
public import Telemetry.Id
public import TelemetryTest.Harness

public section

namespace TelemetryTest.Id

open Telemetry

def isLowercaseHex (s : String) : Bool :=
  s.all fun c => c.isDigit || ('a' ≤ c && c ≤ 'f')

def suite : TestM Unit := do
  property "hex is two characters per byte"
    (∀ bs : List UInt8, (hexOfBytes ⟨bs.toArray⟩).length = 2 * bs.length)
  property "hex uses only lowercase hex digits"
    (∀ bs : List UInt8, isLowercaseHex (hexOfBytes ⟨bs.toArray⟩))
  let traceId ← freshTraceId
  let spanId ← freshSpanId
  checkEq "trace id width" traceId.length 32
  checkEq "span id width" spanId.length 16
  check "trace id is lowercase hex" (isLowercaseHex traceId)
  check "span id is lowercase hex" (isLowercaseHex spanId)
  let child ← SpanContext.child { traceId, spanId }
  checkEq "child keeps the trace" child.traceId traceId
  check "child gets a fresh span id" (child.spanId != spanId)

end TelemetryTest.Id
