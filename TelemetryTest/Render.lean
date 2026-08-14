/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Telemetry.Render
import TelemetryTest.Harness

namespace TelemetryTest.Render

open Telemetry

private def noon : Nat := (12 * 3600 + 4 * 60 + 31) * 1000000000 + 882000000

def suite : TestM Unit := do
  checkEq "time of day is rendered from nanoseconds"
    (Telemetry.Render.timeOfDay (19 * 86400000000000 + noon)) "12:04:31.882"
  checkEq "the epoch renders as midnight" (Telemetry.Render.timeOfDay 0) "00:00:00.000"
  property "time of day is always the same width"
    (∀ n : Nat, (Telemetry.Render.timeOfDay n).length = 12)
  property "a rendered line never contains a newline"
    (∀ (t : Nat) (marker subject key body : String) (n : Int),
      (Telemetry.Render.line t none marker subject [(key, .str body), ("n", .int n)]).all
        (· != '\n'))
  check "a newline in a body cannot break the row"
    ((Telemetry.Render.line 0 none "INFO" "two\nlines" [("k", .str "a\nb")]).all (· != '\n'))
  checkEq "sub-millisecond durations keep a digit" (Telemetry.Render.duration 400000) "0.4ms"
  checkEq "durations are rendered in milliseconds" (Telemetry.Render.duration 8000000) "8.0ms"
  checkEq "a value that would break the columns is quoted"
    (Telemetry.Render.value (.str "two words")) "\"two words\""

end TelemetryTest.Render
