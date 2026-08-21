/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
module

public import Telemetry.Sdk.Data
public import Telemetry.Sdk.Json
public import Telemetry.Sdk.Resource

/-!
OTLP/JSON. Two details deviate from the standard proto3 JSON mapping and are the usual cause of
silently rejected payloads: ids are lowercase hex rather than base64, and 64-bit integers are
decimal strings rather than numbers.
-/

public section

namespace Telemetry.Sdk.Otlp

open Json

def libraryName : String := "lean-telemetry"

def libraryVersion : String := "0.4.0"

@[expose] def kindNumber : SpanKind → Int
  | .internal => 1
  | .server => 2
  | .client => 3
  | .producer => 4
  | .consumer => 5

@[expose] def statusNumber : StatusCode → Int
  | .unset => 0
  | .ok => 1
  | .error => 2

private def int64 (n : Nat) : Json :=
  .str (toString n)

def anyValue : Value → Json
  | .str v => .obj [("stringValue", .str v)]
  | .int v => .obj [("intValue", .str (toString v))]
  | .bool v => .obj [("boolValue", .bool v)]
  | .float v =>
    -- JSON has no infinity or NaN, so a value that cannot be a number is carried as text.
    if v.isFinite then .obj [("doubleValue", .float v)] else .obj [("stringValue", .str (toString v))]
  | .arr vs => .obj [("arrayValue", .obj [("values", .arr (vs.map anyValue))])]

def attributes (attrs : Attrs) : Json :=
  .arr (attrs.map fun (key, v) => .obj [("key", Json.str key), ("value", anyValue v)])

private def status (span : SpanData) : List (String × Json) :=
  if span.status == .unset then
    []
  else
    let code := [("code", Json.num (statusNumber span.status))]
    let message := (span.statusMessage.map fun m => [("message", Json.str m)]).getD []
    [("status", .obj (code ++ message))]

def span (span : SpanData) : Json :=
  .obj (
    [("traceId", Json.str span.ctx.traceId), ("spanId", Json.str span.ctx.spanId)]
      ++ (span.parentSpanId.map fun parent => [("parentSpanId", Json.str parent)]).getD []
      ++ [("name", Json.str span.name),
          ("kind", .num (kindNumber span.kind)),
          ("startTimeUnixNano", int64 span.startUnixNano),
          ("endTimeUnixNano", int64 span.endUnixNano),
          ("attributes", attributes span.attrs)]
      ++ status span)

def logRecord (record : LogRecord) : Json :=
  .obj (
    [("timeUnixNano", int64 record.timeUnixNano),
     ("observedTimeUnixNano", int64 record.timeUnixNano),
     ("severityNumber", Json.num record.severity.number),
     ("severityText", .str record.severity.text),
     ("body", .obj [("stringValue", Json.str record.body)]),
     ("attributes", attributes record.attrs)]
      ++ (match record.ctx with
          | none => []
          | some ctx => [("traceId", Json.str ctx.traceId), ("spanId", Json.str ctx.spanId)]))

private def scope : Json :=
  .obj [("name", Json.str libraryName), ("version", Json.str libraryVersion)]

private def resourceJson (resource : Resource) : Json :=
  .obj [("attributes", attributes resource.attrs)]

/-- One `ExportTraceServiceRequest`, complete in itself, which is why the resource is repeated. -/
def traceRequest (resource : Resource) (spans : Array SpanData) : String :=
  render <| .obj [("resourceSpans", .arr [.obj [
    ("resource", resourceJson resource),
    ("scopeSpans", .arr [.obj [("scope", scope), ("spans", .arr (spans.toList.map span))]])]])]

def logsRequest (resource : Resource) (records : Array LogRecord) : String :=
  render <| .obj [("resourceLogs", .arr [.obj [
    ("resource", resourceJson resource),
    ("scopeLogs", .arr [.obj [("scope", scope),
      ("logRecords", .arr (records.toList.map logRecord))]])]])]

end Telemetry.Sdk.Otlp
