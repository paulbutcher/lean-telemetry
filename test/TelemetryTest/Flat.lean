/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
module

public import Telemetry.Parse.Flat
public import Telemetry.Sdk.Flat
public import TelemetryTest.Harness

public section

namespace TelemetryTest.Flat

open Telemetry Telemetry.Sdk

private def resource : Resource := { attrs := [(Conventions.serviceName, .str "timetabling")] }

private def bare : Resource := { attrs := [] }

private def ctx : SpanContext :=
  { traceId := "4bf92f3577b34da6a3ce929d0e0e4736", spanId := "00f067aa0ba902b7" }

private def root : SpanData where
  ctx := ctx
  parentSpanId := none
  name := "solve"
  kind := .internal
  startUnixNano := 1755172471882000000
  endUnixNano := 1755172471890123456
  attrs := []
  status := .unset
  statusMessage := none

private def record : LogRecord where
  timeUnixNano := 1755172471882000000
  severity := .info
  body := "solve started"
  attrs := []
  ctx := some ctx

private def spanRow (data : SpanData) : String := Sdk.Flat.span resource data

private def logRow (data : LogRecord) : String := Sdk.Flat.logRecord resource data

private def parsed (line : String) : Option Telemetry.Parse.Flat.Row :=
  (Telemetry.Parse.Flat.parse line).toOption

/-!
Two serialisers over one `SpanData` drift: a field is added to the writer and forgotten in the
reader. Reading back what was written is the claim that catches exactly that, and the interesting
cases are escaping and the numeric edges rather than any particular span.

The resource is left empty for the round trip because a row does not record which of its
attributes the resource contributed; denormalising it is what the format is for.

`Value.float` is left out: it is written with the same six decimal places as OTLP/JSON, which is
not enough to name every double, so a round trip through it is not exact and no arrangement of
this format would make it so.
-/

private def roundTrips (data : SpanData) : Bool :=
  parsed (Sdk.Flat.span bare data) == some (.span data)

private def logRoundTrips (data : LogRecord) : Bool :=
  parsed (Sdk.Flat.logRecord bare data) == some (.log data)

/-- A `Plausible` sample is a small `Nat`, and a small number of nanoseconds would never leave
1 January 1970, so each component is scaled to sweep the range that matters for it. -/
private def instant (years days seconds nanos : Nat) : Nat :=
  ((years * 366 + days * 4) * 86400 + seconds * 883) * 1000000000 + nanos * 9721657

/-- Attribute names are prefixed because a name the format reserves is dropped by design, which
is checked on its own below. -/
private def sample (name key body : String) (start duration : Nat) : SpanData :=
  { root with
    name, startUnixNano := start, endUnixNano := start + duration
    parentSpanId := some "e457b5a2e4d86bd1"
    kind := .server
    attrs := [("x." ++ key, .str body), ("x.count", .int 3)]
    status := .error
    statusMessage := some "connection reset" }

private def logSample (body key text : String) (time : Nat) : LogRecord :=
  { record with timeUnixNano := time, body, attrs := [("x." ++ key, .str text)] }

/-!
Each of these mappings is a finite table on both sides, and a wrong entry would put a span in the
wrong bucket in every backend at once, so they are proved rather than sampled.
-/

theorem kind_roundTrips (k : SpanKind) :
    Telemetry.Parse.Flat.kind? (Sdk.Flat.kindText k) = some k := by
  cases k <;> rfl

theorem status_roundTrips (s : StatusCode) :
    Telemetry.Parse.Flat.status? (Sdk.Flat.statusCode s) = some s := by
  cases s <;> rfl

theorem severity_roundTrips (s : Severity) :
    Telemetry.Parse.Flat.severity? s.number = some s := by
  cases s <;> rfl

def suite : TestM Unit := do
  checkEq "a span is one flat object with the resource on it" (spanRow root)
    ("{\"time\":\"2025-08-14T11:54:31.882000000Z\",\"duration_ms\":8.123456,\"name\":\"solve\","
      ++ "\"trace.trace_id\":\"4bf92f3577b34da6a3ce929d0e0e4736\","
      ++ "\"trace.span_id\":\"00f067aa0ba902b7\",\"span.kind\":\"internal\",\"status_code\":0,"
      ++ "\"meta.signal_type\":\"trace\",\"service.name\":\"timetabling\"}")

  checkEq "a log record uses the same envelope" (logRow record)
    ("{\"time\":\"2025-08-14T11:54:31.882000000Z\",\"severity\":\"info\",\"severity_code\":9,"
      ++ "\"body\":\"solve started\",\"trace.trace_id\":\"4bf92f3577b34da6a3ce929d0e0e4736\","
      ++ "\"trace.span_id\":\"00f067aa0ba902b7\",\"meta.signal_type\":\"log\","
      ++ "\"service.name\":\"timetabling\"}")

  check "a root span carries no parent" (!containsText (spanRow root) "trace.parent_id")
  check "a record outside a span carries no ids"
    (!containsText (logRow { record with ctx := none }) "trace.trace_id")

  checkEq "the epoch is midnight" (Sdk.Flat.timestamp 0) "1970-01-01T00:00:00.000000000Z"
  checkEq "a leap day is a day of February"
    (Sdk.Flat.timestamp (1709208000 * 1000000000)) "2024-02-29T12:00:00.000000000Z"
  checkEq "a year divisible by 400 is a leap year"
    (Sdk.Flat.timestamp (951868800 * 1000000000)) "2000-03-01T00:00:00.000000000Z"
  checkEq "a year divisible by 100 is not"
    (Sdk.Flat.timestamp (4133980799 * 1000000000)) "2100-12-31T23:59:59.000000000Z"

  checkEq "a duration keeps its nanoseconds" (Sdk.Flat.durationMillis 8123456) "8.123456"
  checkEq "down to the last one" (Sdk.Flat.durationMillis 1) "0.000001"

  -- Nothing downstream would notice a time that had been rounded, which is why it is written as
  -- text rather than as the number a query engine would find friendlier.
  check "a time is not written as a number that would round"
    (containsText (spanRow root) "\"time\":\"2025-08-14T11:54:31.882000000Z\"")

  let impostor := { root with attrs := [("name", .str "elsewhere"), ("x.kept", .int 1)] }
  check "an attribute may not displace the field it is named after"
    (containsText (spanRow impostor) "\"name\":\"solve\"" &&
      !containsText (spanRow impostor) "elsewhere")
  check "and its neighbours are kept" (containsText (spanRow impostor) "\"x.kept\":1")

  checkEq "a span's own attributes outrank the resource's"
    (parsed (Sdk.Flat.span resource { root with attrs := [(Conventions.serviceName, .str "solver")] }))
    (some (.span { root with attrs := [(Conventions.serviceName, .str "solver")] }))

  check "a row of the other signal is not mistaken for this one"
    ((Telemetry.Parse.Flat.parse (logRow record)).toOption != some (.span root))
  check "a row missing a field it needs is refused"
    ((Telemetry.Parse.Flat.parse "{\"meta.signal_type\":\"trace\"}").toOption.isNone)
  check "a time before the epoch is refused rather than wrapping"
    ((Telemetry.Parse.Flat.unixNano "1969-12-31T23:59:59.999999999Z").toOption.isNone)

  check "a record with no span context comes back with none"
    (logRoundTrips { record with ctx := none })
  check "an unset status and an absent parent come back as they went" (roundTrips root)

  property "a span survives the round trip"
    (∀ (name key body : String) (years days seconds nanos duration : Nat),
      roundTrips (sample name key body (instant years days seconds nanos) (duration * 997)))
  property "a log record survives the round trip"
    (∀ (body key text : String) (years days seconds nanos : Nat),
      logRoundTrips (logSample body key text (instant years days seconds nanos)))
  property "a span is one line whatever its attributes hold"
    (∀ name key body : String,
      (spanRow (sample name key body 0 1)).all (· != '\n'))
  property "a log record is one line whatever its body holds"
    (∀ body key text : String, (logRow (logSample body key text 0)).all (· != '\n'))

end TelemetryTest.Flat
