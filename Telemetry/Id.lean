/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
module

public import Telemetry.Context

public section

namespace Telemetry

def hexDigit (n : UInt8) : Char :=
  if n < 10 then
    Char.ofNat ('0'.toNat + n.toNat)
  else
    Char.ofNat ('a'.toNat + n.toNat - 10)

def hexOfBytes (bytes : ByteArray) : String :=
  bytes.foldl (init := "") fun acc b =>
    (acc.push (hexDigit (b >>> 4))).push (hexDigit (b &&& 0xf))

def freshTraceId : IO String := hexOfBytes <$> IO.getRandomBytes 16

def freshSpanId : IO String := hexOfBytes <$> IO.getRandomBytes 8

def SpanContext.root : IO SpanContext :=
  return { traceId := ← freshTraceId, spanId := ← freshSpanId }

/-- A child shares its parent's trace, so only the span id is fresh. -/
def SpanContext.child (parent : SpanContext) : IO SpanContext :=
  return { parent with spanId := ← freshSpanId }

end Telemetry
