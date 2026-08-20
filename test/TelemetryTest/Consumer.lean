/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
module

public import Telemetry.Testing
public import TelemetryTest.Harness

/-!
The claims an application instrumented against this library wants to make about itself, written
the way its own test suite would write them, so that the testing library is exercised from
outside as well as by the SDK.
-/

public section

namespace TelemetryTest.Consumer

open Telemetry Telemetry.Testing

private def template : String := "/todos/:id/edit"

private def matchesTemplate (path : String) : Bool :=
  let segments := template.splitOn "/"
  let actual := path.splitOn "/"
  segments.length == actual.length &&
    (segments.zip actual).all fun (segment, actual) =>
      segment.startsWith ":" || segment == actual

/-- Instrumentation of the kind an HTTP adapter carries, in miniature. -/
private def handle (path : String) : TelemetryT IO (Option Dynamic) :=
  span "GET" (kind := .server) fun s => do
    if matchesTemplate path then
      s.rename template
      s.add [(Conventions.httpRoute, template)]
    if path == "/boom" then
      throw (IO.userError "no such todo")
    return s.context.map Dynamic.mk

/-- The context travels as an opaque box, as it would in a framework's typed extensions map. -/
private def query (carrier : Option Dynamic) : IO Unit :=
  runTelemetry <|
    withSpanContext (carrier.bind (·.get? SpanContext)) <|
      spanning "SELECT todos" (kind := .client) (pure ())

private def request (path : String) : IO Captured := do
  let ((), captured) ← capture do
    let carrier ← runTelemetry (handle path)
    query carrier
  return captured

private def failingRequest : IO (Bool × Captured) :=
  capture do
    try
      let _ ← runTelemetry (handle "/boom")
      pure false
    catch _ =>
      pure true

def suite : TestM Unit := do
  let captured ← request "/todos/99/edit"
  checkEq "the server span is named for the route template rather than the path"
    (captured.spans.filter (·.kind == .server) |>.map (·.name)) #[template]
  checkEq "and carries the template as an attribute"
    (captured.spans.filterMap (·.attrs.lookup Conventions.httpRoute)) #[Value.str template]

  let unrouted ← request "/nothing/here"
  check "a request that matched no route claims no route at all"
    (unrouted.spans.all (·.attrs.lookup Conventions.httpRoute == none))

  match captured.spans.find? (·.kind == .server),
      captured.spans.find? (·.kind == .client) with
  | some server, some client =>
    checkEq "the database span is a child of the request's span"
      client.parentSpanId (some server.ctx.spanId)
    checkEq "and shares its trace" client.ctx.traceId server.ctx.traceId
  | _, _ =>
    failure "expected both a server span and a client span"

  let (threw, failed) ← failingRequest
  check "an exception from a handler is re-raised rather than swallowed" threw
  checkEq "the span it escaped is marked as an error"
    (failed.spans.map (·.status)) #[StatusCode.error]
  check "carrying the exception's message"
    (failed.spans.all (·.statusMessage.any (containsText · "no such todo")))

end TelemetryTest.Consumer
