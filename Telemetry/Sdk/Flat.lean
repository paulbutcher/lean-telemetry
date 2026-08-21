/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
module

public import Telemetry.Sdk.Data
public import Telemetry.Sdk.Json
public import Telemetry.Sdk.Resource

/-!
One self-contained JSON object per span or log record, with the resource denormalised onto every
row, for the row-oriented stores that cannot address a value buried in an OTLP envelope. The
field names are Honeycomb's, so the same bytes are ingestible by their events API and queryable
in CloudWatch Logs Insights or Athena.

Attribute names are emitted verbatim, dots and all: `http.route` as a literal key and
`{"http":{"route":...}}` are addressed identically by those engines, so the flat spelling is both
correct and cheaper.

No number here passes through a `Float`. Nanoseconds since the epoch are past the range a double
represents exactly, so a time is written as RFC 3339 text and a duration as decimal digits.
-/

public section

namespace Telemetry.Sdk.Flat

open Json

namespace Field

def time : String := "time"
def durationMs : String := "duration_ms"
def name : String := "name"
def traceId : String := "trace.trace_id"
def spanId : String := "trace.span_id"
def parentId : String := "trace.parent_id"
def kind : String := "span.kind"
def statusCode : String := "status_code"
def statusMessage : String := "status_message"
def signalType : String := "meta.signal_type"
def severity : String := "severity"
def severityCode : String := "severity_code"
def body : String := "body"

end Field

/--
The names the format owns. A row carries either signal, so this is one set rather than one per
signal: an attribute named `body` is dropped from a span as well as from a log record.
-/
def reserved : List String :=
  [Field.time, Field.durationMs, Field.name, Field.traceId, Field.spanId, Field.parentId,
    Field.kind, Field.statusCode, Field.statusMessage, Field.signalType, Field.severity,
    Field.severityCode, Field.body]

def traceSignal : String := "trace"

def logSignal : String := "log"

@[expose] def kindText : SpanKind → String
  | .internal => "internal"
  | .server => "server"
  | .client => "client"
  | .producer => "producer"
  | .consumer => "consumer"

/-- The OTLP status numbers, which is what Honeycomb's `status_code` carries. -/
@[expose] def statusCode : StatusCode → Int
  | .unset => 0
  | .ok => 1
  | .error => 2

private def digits (width : Nat) (n : Nat) : String :=
  let s := toString n
  if s.length ≥ width then s else "".pushn '0' (width - s.length) ++ s

/--
Howard Hinnant's `civil_from_days`, whose era begins on 1 March so that a leap day falls at the
end of a year rather than in the middle of one.
-/
@[expose] def civilFromDays (days : Nat) : Nat × Nat × Nat :=
  let z := days + 719468
  let era := z / 146097
  let doe := z % 146097
  let yoe := (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
  let doy := doe - (365 * yoe + yoe / 4 - yoe / 100)
  let mp := (5 * doy + 2) / 153
  let day := doy - (153 * mp + 2) / 5 + 1
  let month := if mp < 10 then mp + 3 else mp - 9
  let year := yoe + era * 400
  (if month ≤ 2 then year + 1 else year, month, day)

/-- RFC 3339 in UTC. Nine fractional digits are exactly the nanosecond count. -/
def timestamp (unixNano : Nat) : String :=
  let seconds := unixNano / 1000000000
  let (year, month, day) := civilFromDays (seconds / 86400)
  let secondOfDay := seconds % 86400
  let date := s!"{digits 4 year}-{digits 2 month}-{digits 2 day}"
  let clock := s!"{digits 2 (secondOfDay / 3600)}:{digits 2 (secondOfDay / 60 % 60)}:{digits 2 (secondOfDay % 60)}"
  s!"{date}T{clock}.{digits 9 (unixNano % 1000000000)}Z"

/-- Six decimal places are exactly the nanosecond count, and read as a number by every engine
this format targets. -/
def durationMillis (nanos : Nat) : String :=
  s!"{nanos / 1000000}.{digits 6 (nanos % 1000000)}"

def value : Value → Json
  | .str v => .str v
  | .int v => .num v
  | .bool v => .bool v
  -- JSON has no infinity or NaN, so a value that cannot be a number is carried as text.
  | .float v => if v.isFinite then .float v else .str (toString v)
  | .arr vs => .arr (vs.map value)

/-- Reserved names win: an attribute may not displace the field the format defines, so one that
would is dropped. -/
private def attributes (attrs : Attrs) : List (String × Json) :=
  attrs.filterMap fun (key, v) => if reserved.contains key then none else some (key, value v)

/-- The resource sits below the record's own attributes, so a span can say what its process
cannot know. -/
private def denormalised (resource : Resource) (attrs : Attrs) : List (String × Json) :=
  attributes (Resource.merge resource.attrs attrs)

def span (resource : Resource) (span : SpanData) : String :=
  render <| .obj (
    [(Field.time, Json.str (timestamp span.startUnixNano)),
     (Field.durationMs, .decimal (durationMillis span.durationNanos)),
     (Field.name, .str span.name),
     (Field.traceId, .str span.ctx.traceId),
     (Field.spanId, .str span.ctx.spanId)]
      ++ (span.parentSpanId.map fun parent => [(Field.parentId, Json.str parent)]).getD []
      ++ [(Field.kind, Json.str (kindText span.kind)),
          (Field.statusCode, .num (statusCode span.status))]
      ++ (span.statusMessage.map fun m => [(Field.statusMessage, Json.str m)]).getD []
      ++ [(Field.signalType, Json.str traceSignal)]
      ++ denormalised resource span.attrs)

def logRecord (resource : Resource) (record : LogRecord) : String :=
  render <| .obj (
    [(Field.time, Json.str (timestamp record.timeUnixNano)),
     (Field.severity, .str record.severity.text.toLower),
     (Field.severityCode, .num (record.severity.number : Int)),
     (Field.body, .str record.body)]
      ++ (match record.ctx with
          | none => []
          | some ctx => [(Field.traceId, Json.str ctx.traceId), (Field.spanId, .str ctx.spanId)])
      ++ [(Field.signalType, Json.str logSignal)]
      ++ denormalised resource record.attrs)

end Telemetry.Sdk.Flat
