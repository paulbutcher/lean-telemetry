/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Telemetry.Sdk.Json
import TelemetryTest.Harness

namespace TelemetryTest.Json

open Telemetry.Sdk

def suite : TestM Unit := do
  checkEq "a newline is escaped rather than emitted"
    (Telemetry.Sdk.Json.escape "two\nlines") "two\\nlines"
  checkEq "quotes and backslashes are escaped"
    (Telemetry.Sdk.Json.escape "say \"hi\\bye\"") "say \\\"hi\\\\bye\\\""
  checkEq "other control characters take the \\u form"
    (Telemetry.Sdk.Json.escape "\x0b") "\\u000b"
  checkEq "printable characters are left alone"
    (Telemetry.Sdk.Json.escape "solver.strategy=greedy") "solver.strategy=greedy"

  -- A newline here would split one JSONL record into two, which no reader recovers from, so
  -- this wants to be a theorem. It resists proof only because the `\u` branch defers to a
  -- private helper, which a test cannot name and so cannot reason about.
  property "no input can put a newline in a JSON string"
    (∀ s : String, (Telemetry.Sdk.Json.escape s).all (· != '\n'))

end TelemetryTest.Json
