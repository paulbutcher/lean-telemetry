/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Telemetry.Sdk.Otlp
import TelemetryTest.Harness

namespace TelemetryTest.Otlp

open Telemetry Telemetry.Sdk

private def resource : Resource := { attrs := [(Conventions.serviceName, .str "timetabling")] }

private def ctx : SpanContext :=
  { traceId := "4bf92f3577b34da6a3ce929d0e0e4736", spanId := "00f067aa0ba902b7" }

private def root : SpanData where
  ctx := ctx
  parentSpanId := none
  name := "solve"
  kind := .internal
  startUnixNano := 1755172471882000000
  endUnixNano := 1755172471890000000
  attrs := []
  status := .unset
  statusMessage := none

private def child : SpanData :=
  { root with
    parentSpanId := some "e457b5a2e4d86bd1"
    name := "GET /schools/{id}"
    kind := .server
    attrs := [(Conventions.httpResponseStatusCode, 200)]
    status := .error
    statusMessage := some "connection reset" }

private def record : LogRecord where
  timeUnixNano := 1755172471882000000
  severity := .info
  body := "solve started"
  attrs := []
  ctx := some ctx

private def spans (data : SpanData) : String := Telemetry.Sdk.Otlp.traceRequest resource #[data]

private def logs (data : LogRecord) : String := Telemetry.Sdk.Otlp.logsRequest resource #[data]

private def encodedValue (v : Value) : String :=
  Telemetry.Sdk.Json.render (Telemetry.Sdk.Otlp.anyValue v)

/-!
A backend can only tell two spans apart if the wire form does, so each of these encodings has
to be injective. Nothing downstream would notice two cases sharing a number, which is what
makes it worth proving rather than sampling.
-/

theorem kindNumber_inj (a b : SpanKind)
    (h : Telemetry.Sdk.Otlp.kindNumber a = Telemetry.Sdk.Otlp.kindNumber b) : a = b := by
  cases a <;> cases b <;> simp_all [Telemetry.Sdk.Otlp.kindNumber]

theorem statusNumber_inj (a b : StatusCode)
    (h : Telemetry.Sdk.Otlp.statusNumber a = Telemetry.Sdk.Otlp.statusNumber b) : a = b := by
  cases a <;> cases b <;> simp_all [Telemetry.Sdk.Otlp.statusNumber]

theorem severityNumber_inj (a b : Severity) (h : a.number = b.number) : a = b := by
  cases a <;> cases b <;> simp_all [Severity.number]

theorem severityText_inj (a b : Severity) (h : a.text = b.text) : a = b := by
  cases a <;> cases b <;> simp_all [Severity.text]

def suite : TestM Unit := do
  checkEq "a root span encodes to a complete request" (spans root)
    ("{\"resourceSpans\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"timetabling\"}}]},\"scopeSpans\":[{\"scope\":{\"name\":\"lean-telemetry\",\"version\":\"" ++ Telemetry.Sdk.Otlp.libraryVersion ++ "\"},\"spans\":[{\"traceId\":\"4bf92f3577b34da6a3ce929d0e0e4736\",\"spanId\":\"00f067aa0ba902b7\",\"name\":\"solve\",\"kind\":1,\"startTimeUnixNano\":\"1755172471882000000\",\"endTimeUnixNano\":\"1755172471890000000\",\"attributes\":[]}]}]}]}")

  check "a root span carries no parent" (!containsText (spans root) "parentSpanId")
  check "an unset status is omitted" (!containsText (spans root) "status")

  check "a child names its parent"
    (containsText (spans child) "\"parentSpanId\":\"e457b5a2e4d86bd1\"")
  check "an error status carries its message"
    (containsText (spans child) "\"status\":{\"code\":2,\"message\":\"connection reset\"}")
  check "a server span is kind 2" (containsText (spans child) "\"kind\":2")
  check "64-bit integers are decimal strings"
    (containsText (spans child) "\"startTimeUnixNano\":\"1755172471882000000\"")
  check "an ok status is code 1"
    (containsText (spans { root with status := .ok }) "\"status\":{\"code\":1}")

  checkEq "strings" (encodedValue (.str "postgresql")) "{\"stringValue\":\"postgresql\"}"
  checkEq "integers are strings, not numbers" (encodedValue (.int 200)) "{\"intValue\":\"200\"}"
  checkEq "booleans" (encodedValue (.bool true)) "{\"boolValue\":true}"
  checkEq "floats stay numbers"
    (encodedValue (.float 0.25)) s!"\{\"doubleValue\":{toString (0.25 : Float)}}"
  checkEq "arrays nest their values"
    (encodedValue (.arr [.int 1, .str "a"]))
    "{\"arrayValue\":{\"values\":[{\"intValue\":\"1\"},{\"stringValue\":\"a\"}]}}"
  check "a value JSON cannot represent is not silently a number"
    (containsText (encodedValue (.float (1.0 / 0.0))) "stringValue")

  checkEq "a log record encodes to a complete request" (logs record)
    ("{\"resourceLogs\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"timetabling\"}}]},\"scopeLogs\":[{\"scope\":{\"name\":\"lean-telemetry\",\"version\":\"" ++ Telemetry.Sdk.Otlp.libraryVersion ++ "\"},\"logRecords\":[{\"timeUnixNano\":\"1755172471882000000\",\"observedTimeUnixNano\":\"1755172471882000000\",\"severityNumber\":9,\"severityText\":\"INFO\",\"body\":{\"stringValue\":\"solve started\"},\"attributes\":[],\"traceId\":\"4bf92f3577b34da6a3ce929d0e0e4736\",\"spanId\":\"00f067aa0ba902b7\"}]}]}]}")

  check "a record outside a span carries no ids"
    (!containsText (logs { record with ctx := none }) "traceId")
  check "severity numbers follow the record's severity"
    (containsText (logs { record with severity := .fatal }) "\"severityNumber\":21,\"severityText\":\"FATAL\"")

  property "a span is one line whatever its attributes hold"
    (∀ name key body : String,
      (spans { root with name, attrs := [(key, .str body)] }).all (· != '\n'))
  property "a log record is one line whatever its body holds"
    (∀ body key text : String,
      (logs { record with body, attrs := [(key, .str text)] }).all (· != '\n'))

end TelemetryTest.Otlp
