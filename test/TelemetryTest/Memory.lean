/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Telemetry.Sdk.Exporter

namespace TelemetryTest

open Telemetry Telemetry.Sdk

/-- An exporter that keeps what it is given, so installation can be exercised without a stream. -/
structure Memory where
  spans : IO.Ref (Array SpanData)
  logs : IO.Ref (Array LogRecord)
  shutdowns : IO.Ref Nat

def Memory.new : IO Memory :=
  return { spans := ← IO.mkRef #[], logs := ← IO.mkRef #[], shutdowns := ← IO.mkRef 0 }

def Memory.exporter (memory : Memory) : Exporter where
  exportSpans spans := memory.spans.modify (· ++ spans)
  exportLogs logs := memory.logs.modify (· ++ logs)
  shutdown := memory.shutdowns.modify (· + 1)

end TelemetryTest
