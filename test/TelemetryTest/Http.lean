/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Std.Http.Server
import Telemetry.Sdk.Http
import Telemetry.Sdk.Install
import TelemetryTest.Harness

namespace TelemetryTest.Http

open Telemetry Telemetry.Sdk
open Std.Async Std.Http

private def resource : Resource := { attrs := [(Conventions.serviceName, .str "timetabling")] }

private def ctx : SpanContext :=
  { traceId := "4bf92f3577b34da6a3ce929d0e0e4736", spanId := "00f067aa0ba902b7" }

private def sampleSpan : SpanData where
  ctx := ctx
  parentSpanId := none
  name := "solve"
  kind := .internal
  startUnixNano := 1755172471882000000
  endUnixNano := 1755172471890000000
  attrs := []
  status := .unset
  statusMessage := none

private def sampleLog : LogRecord where
  timeUnixNano := 1755172471882000000
  severity := .info
  body := "solve started"
  attrs := []
  ctx := some ctx

private structure Arrived where
  method : String
  target : String
  contentType : Option String
  body : String

private def headerValue (headers : Headers) (name : String) : Option String :=
  headers.toList.find? (fun (key, _) => (toString key).toLower == name) |>.map (toString ·.2)

private def recording (received : IO.Ref (Array Arrived)) : Server.StatelessHandler :=
  Server.Handler.ofFn fun request => do
    let body : String ← request.body.readAll
    received.modify (·.push {
      method := toString request.line.method
      target := toString request.line.uri
      contentType := headerValue request.line.headers "content-type"
      body })
    Response.ok |>.text "{}"

/-- An operating-system-chosen loopback port, so that a test never collides with anything. -/
private def serving (handler : Server.StatelessHandler) (action : String → IO Unit) : IO Unit := do
  let server ← (Server.serve (.v4 ⟨.ofParts 127 0 0 1, 0⟩) handler).block
  try
    action s!"http://127.0.0.1:{(server.localAddr.map (·.port)).getD 0}"
  finally
    server.shutdownAndWait.block

private def withCollector (action : String → IO Unit) : IO (Array Arrived) := do
  let received ← IO.mkRef (#[] : Array Arrived)
  serving (recording received) action
  received.get

/-- A collector that refuses the first export and accepts the next, as one still starting up
would. -/
private def flaky (calls : IO.Ref Nat) : Server.StatelessHandler :=
  Server.Handler.ofFn fun request => do
    let _ : String ← request.body.readAll
    let seen ← calls.modifyGet fun n => (n, n + 1)
    if seen == 0 then Response.serviceUnavailable |>.text "starting" else Response.ok |>.text "{}"

private def acrossAnOutage : IO String := do
  let captured ← IO.mkRef { : IO.FS.Stream.Buffer }
  let calls ← IO.mkRef 0
  IO.withStderr (IO.FS.Stream.ofBuffer captured) do
    serving (flaky calls) fun endpoint => do
      let exporter ← Http.otlpJson resource (Http.resolve (some endpoint) none none 2000)
      exporter.exportSpans #[sampleSpan]
      exporter.exportSpans #[sampleSpan]
  bufferText captured

private def exportBoth (endpoint : String) : IO Unit := do
  let exporter ← Http.otlpJson resource (Http.resolve (some endpoint) none none 2000)
  exporter.exportSpans #[sampleSpan]
  exporter.exportLogs #[sampleLog]

/--
Nothing is listening on port 1, which is privileged. This is the case that matters in production:
an application must not see a request fail because a collector did not answer.
-/
private def againstNothing : IO (Nat × String) := do
  let captured ← IO.mkRef { : IO.FS.Stream.Buffer }
  let answer ← IO.withStderr (IO.FS.Stream.ofBuffer captured) do
    let exporter ← Http.otlpJson resource (Http.resolve (some "http://127.0.0.1:1") none none 2000)
    install resource #[exporter]
    try
      runTelemetry do
        spanning "unreachable" do
          info "still runs"
          pure 42
    finally
      Telemetry.Sdk.shutdown
  return (answer, ← bufferText captured)

/-!
Reversing these two is the classic OTLP configuration bug. A signal endpoint that gained a path
would post to `/v1/traces/v1/traces`, and a base endpoint that did not would post to whatever the
collector serves at its root, so both hold for every endpoint rather than for the ones a
generator happens to produce.
-/

theorem signalEndpointUsedAsGiven (base logs : Option String) (traces : String) (timeout : Nat) :
    (Telemetry.Sdk.Http.resolve base (some traces) logs timeout).traces = traces := rfl

theorem baseEndpointGainsSignalPath (base : String) (timeout : Nat) :
    (Telemetry.Sdk.Http.resolve (some base) none none timeout).logs
      = Telemetry.Sdk.Http.signalUrl base Telemetry.Sdk.Http.logsPath := rfl

def suite : TestM Unit := do
  checkEq "a base endpoint gains the signal path"
    (Http.resolve (some "http://collector:4318") none none 0).traces
    "http://collector:4318/v1/traces"
  checkEq "a trailing separator on the base does not double up"
    (Http.resolve (some "http://collector:4318/") none none 0).logs
    "http://collector:4318/v1/logs"
  checkEq "with nothing set at all, the collector is the local one"
    Http.default.traces "http://localhost:4318/v1/traces"

  let arrived ← withCollector exportBoth
  checkEq "one request arrives per export" arrived.size 2
  checkEq "each is a POST" (arrived.map (·.method)) #["POST", "POST"]
  checkEq "each carries its signal's path" (arrived.map (·.target)) #["/v1/traces", "/v1/logs"]
  checkEq "each is announced as JSON" (arrived.map (·.contentType))
    #[some "application/json", some "application/json"]
  checkEq "the span arrives as the encoder wrote it"
    (arrived[0]?.map (·.body)) (some (Otlp.traceRequest resource #[sampleSpan]))
  checkEq "and so does the log record"
    (arrived[1]?.map (·.body)) (some (Otlp.logsRequest resource #[sampleLog]))

  -- The log record and the span are two separate exports, and both fail.
  let (answer, reported) ← againstNothing
  checkEq "an unreachable collector does not reach the caller" answer 42
  checkEq "an outage is reported once, not once per export"
    (reported.splitOn "\n").length 2
  check "and says where it was trying to reach"
    (containsText reported "http://127.0.0.1:1/")

  let outage ← acrossAnOutage
  check "a collector that answers but refuses the payload is reported"
    (containsText outage "503")
  check "and its recovery accounts for what was lost"
    (containsText outage "1 export(s) were dropped")

end TelemetryTest.Http
