/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Telemetry.Logging
import Telemetry.Trace
import TelemetryTest.Harness
import TelemetryTest.Recorder

namespace TelemetryTest.Logging

open Telemetry

private def recorded : IO (Array LogRecord) :=
  withRecorder fun recorder => do
    runTelemetry do
      info "outside a span" [("attempt", 1)]
      spanning "work" do
        error "inside a span"
    recorder.logs.get

private def captured (act : IO Unit) : IO (String × String) := do
  let out ← IO.mkRef { : IO.FS.Stream.Buffer }
  let err ← IO.mkRef { : IO.FS.Stream.Buffer }
  IO.withStdout (IO.FS.Stream.ofBuffer out) <| IO.withStderr (IO.FS.Stream.ofBuffer err) act
  return (String.fromUTF8! (← out.get).data, String.fromUTF8! (← err.get).data)

private def withoutSdk : IO (String × String) := do
  clearHooks
  captured <| runTelemetry do
    info "readable on stdout"
    error "readable on stderr"

/--
Which stream a record goes to is decided by comparing severity numbers, so nothing in the
definition names the two severities it actually selects.
-/
theorem isError_iff (s : Severity) : s.isError = (s == .error || s == .fatal) := by
  cases s <;> rfl

def suite : TestM Unit := do
  let logs ← recorded
  checkEq "both records reach the SDK" logs.size 2
  if h : logs.size = 2 then
    let outside := logs[0]'(by omega)
    let inside := logs[1]'(by omega)
    checkEq "a record outside a span has no context" outside.ctx none
    checkEq "the body is carried through" outside.body "outside a span"
    checkEq "the attributes are carried through" outside.attrs [("attempt", (1 : Value))]
    checkEq "the severity is carried through" outside.severity Severity.info
    check "a record inside a span carries its context" inside.ctx.isSome
  else
    pure ()

  let (out, err) ← withoutSdk
  check "with no SDK an ordinary record still reaches stdout"
    (containsText out "readable on stdout")
  check "with no SDK an error record reaches stderr"
    (containsText err "readable on stderr")
  check "the two streams are kept apart" (!containsText out "readable on stderr")
  check "the readable line names the severity" (containsText out "INFO")
  checkEq "one record is one line" (out.splitOn "\n").length 2

end TelemetryTest.Logging
