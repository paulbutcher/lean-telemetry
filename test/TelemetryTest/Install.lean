/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Telemetry.Sdk.Install
import Telemetry.Testing
import TelemetryTest.Harness

namespace TelemetryTest.Install

open Telemetry Telemetry.Sdk Telemetry.Testing

private structure Outcome where
  first : Recorder
  second : Recorder
  afterShutdown : Nat

private def fanOut : IO Outcome := do
  let first ← Recorder.new
  let second ← Recorder.new
  install { attrs := [] } #[first.exporter, second.exporter]
  runTelemetry do
    spanning "work" (attrs := [("k", "v")]) do
      info "inside"
  Telemetry.Sdk.flush
  Telemetry.Sdk.shutdown
  runTelemetry (spanning "after shutdown" (pure ()))
  return { first, second, afterShutdown := (← first.spans.get).size }

private def configuredEnvironment : IO Bool := do
  for name in ["OTEL_SDK_DISABLED", "OTEL_TRACES_EXPORTER", "OTEL_LOGS_EXPORTER",
      "OTEL_EXPORTER_CONSOLE_FORMAT"] do
    if (← IO.getEnv name).isSome then
      return true
  return false

/-- The default installation, which is what an application with no collector at all gets. -/
private def defaultInstallation : IO String := do
  let out ← IO.mkRef { : IO.FS.Stream.Buffer }
  IO.withStdout (IO.FS.Stream.ofBuffer out) do
    installFromEnv
    runTelemetry (spanning "default install" (pure ()))
    Telemetry.Sdk.shutdown
  bufferText out

def suite : TestM Unit := do
  let outcome ← fanOut
  let spans ← outcome.first.spans.get
  let logs ← outcome.first.logs.get
  let otherSpans ← outcome.second.spans.get
  let otherLogs ← outcome.second.logs.get
  checkEq "the span reaches the first exporter" (spans.map (·.name)) #["work"]
  checkEq "and the second" (otherSpans.map (·.name)) #["work"]
  checkEq "the log record reaches the first exporter" (logs.map (·.body)) #["inside"]
  checkEq "and the second" (otherLogs.map (·.body)) #["inside"]
  check "the record is tied to the span"
    (logs.any fun record => spans.any fun span => record.ctx.any (·.spanId == span.ctx.spanId))
  checkEq "call site attributes survive the round trip"
    (spans.map (·.attrs)) #[[("k", Value.str "v")]]
  checkEq "shutdown reaches every exporter"
    ((← outcome.first.shutdowns.get), (← outcome.second.shutdowns.get)) (1, 1)
  checkEq "after shutdown nothing more is reported" outcome.afterShutdown 1

  unless ← configuredEnvironment do
    let printed ← defaultInstallation
    check "with nothing configured, spans are readable on stdout"
      (containsText printed "default install")
    checkEq "one span is one line" (printed.splitOn "\n").length 2

end TelemetryTest.Install
