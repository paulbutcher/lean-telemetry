/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
module

public import Telemetry.Parse.Json
public import Telemetry.Sdk.Flat

/-!
The flat format read back: a row becomes the `SpanData` or `LogRecord` it was written from, so
that a terminal tool can render deployed output in the readable form and a forwarder can turn it
back into OTLP.

A row that came from a resource carries the resource's attributes among its own; nothing on the
row says which were which, so they arrive as attributes of the span or record.
-/

public section

namespace Telemetry.Parse.Flat

open Telemetry.Sdk.Flat

inductive Row where
  | span (data : Sdk.SpanData)
  | log (record : LogRecord)
  deriving Repr, BEq, Inhabited

@[expose] def kind? : String → Option SpanKind
  | "internal" => some .internal
  | "server" => some .server
  | "client" => some .client
  | "producer" => some .producer
  | "consumer" => some .consumer
  | _ => none

@[expose] def status? : Int → Option StatusCode
  | 0 => some .unset
  | 1 => some .ok
  | 2 => some .error
  | _ => none

/-- OTLP leaves room between its severity numbers for finer gradations, and a record that used
one belongs in the bucket below it. -/
@[expose] def severity? (code : Nat) : Option Severity :=
  if code ≥ Severity.fatal.number then some .fatal
  else if code ≥ Severity.error.number then some .error
  else if code ≥ Severity.warn.number then some .warn
  else if code ≥ Severity.info.number then some .info
  else if code ≥ Severity.debug.number then some .debug
  else if code ≥ Severity.trace.number then some .trace
  else none

private def splitOnce (sep : String) (s : String) : String × Option String :=
  match s.splitOn sep with
  | [] => ("", none)
  | [only] => (only, none)
  | first :: rest => (first, some (String.intercalate sep rest))

/-- A decimal number as an exact count of units of `10 ^ -places`, read from its digits so that
nothing passes through a `Float`. -/
private def scaled (places : Nat) (text : String) : Except String Nat :=
  let (whole, fraction) := splitOnce "." text
  let padded := (((fraction.getD "") ++ "".pushn '0' places).take places).toString
  match ("0" ++ whole).toNat?, ("0" ++ padded).toNat? with
  | some units, some fraction => .ok (units * 10 ^ places + fraction)
  | _, _ => .error s!"'{text}' is not a decimal number"

/-- The inverse of `civilFromDays`, counting from the same 1 March origin. -/
private def daysSinceOrigin (year month day : Nat) : Nat :=
  let y := if month ≤ 2 then year - 1 else year
  let era := y / 400
  let yoe := y % 400
  let mp := if month > 2 then month - 3 else month + 9
  let doy := (153 * mp + 2) / 5 + day - 1
  era * 146097 + yoe * 365 + yoe / 4 - yoe / 100 + doy

/-- RFC 3339 in UTC, with however many fractional digits it was written with. -/
def unixNano (text : String) : Except String Nat := do
  let malformed := s!"'{text}' is not an RFC 3339 time in UTC"
  let (date, afterDate) := splitOnce "T" text
  let some clock := afterDate | .error malformed
  unless clock.endsWith "Z" do .error malformed
  match date.splitOn "-", (clock.dropEnd 1).toString.splitOn ":" with
  | [year, month, day], [hour, minute, second] =>
    match year.toNat?, month.toNat?, day.toNat?, hour.toNat?, minute.toNat? with
    | some year, some month, some day, some hour, some minute =>
      if month < 1 || month > 12 || day < 1 || day > 31 || hour > 23 || minute > 59 then
        .error malformed
      else
        let days := daysSinceOrigin year month day
        if days < 719468 then
          .error s!"'{text}' precedes 1970, which nanoseconds since the epoch cannot reach"
        else
          return ((days - 719468) * 86400 + hour * 3600 + minute * 60) * 1000000000
            + (← scaled 9 second)
    | _, _, _, _, _ => .error malformed
  | _, _ => .error malformed

/-- Rebuilt from its digits rather than accumulated by arithmetic, so the value is rounded once
rather than once per digit. -/
private def float? (text : String) : Option Float := do
  let (negative, text) :=
    if text.startsWith "-" then (true, (text.drop 1).toString) else (false, text)
  let (mantissa, exponentText) := splitOnce "e" text.toLower
  let (whole, fraction) := splitOnce "." mantissa
  let fraction := fraction.getD ""
  let digits ← (whole ++ fraction).toNat?
  let exponent : Int ←
    match exponentText with
    | none => some 0
    | some e => (if e.startsWith "+" then (e.drop 1).toString else e).toInt?
  let scale := exponent - fraction.length
  let magnitude :=
    if scale ≥ 0 then Float.ofScientific digits false scale.toNat
    else Float.ofScientific digits true (-scale).toNat
  return if negative then -magnitude else magnitude

/-- A number with a fraction or an exponent is a `Float`; anything else is an integer, which is
the distinction the writer makes in the other direction. -/
private def number (text : String) : Except String Value :=
  if text.any fun c => c == '.' || c == 'e' || c == 'E' then
    match float? text with
    | some v => .ok (.float v)
    | none => .error s!"'{text}' is not a number"
  else
    match text.toInt? with
    | some v => .ok (.int v)
    | none => .error s!"'{text}' is not a number"

mutual

private def attributeValue : Json → Except String Value
  | .str v => .ok (.str v)
  | .bool v => .ok (.bool v)
  | .num text => number text
  | .arr items => (Value.arr ·) <$> attributeValues items
  | .obj _ => .error "an attribute cannot be an object"
  | .null => .error "an attribute cannot be null"

private def attributeValues : List Json → Except String (List Value)
  | [] => .ok []
  | item :: rest => return (← attributeValue item) :: (← attributeValues rest)

end

private def field (fields : List (String × Json)) (key : String) : Except String Json :=
  match fields.lookup key with
  | some json => .ok json
  | none => .error s!"'{key}' is missing"

private def string (fields : List (String × Json)) (key : String) : Except String String := do
  match ← field fields key with
  | .str v => .ok v
  | _ => .error s!"'{key}' is not a string"

private def optional (fields : List (String × Json)) (key : String) :
    Except String (Option String) :=
  match fields.lookup key with
  | none => .ok none
  | some (.str v) => .ok (some v)
  | some _ => .error s!"'{key}' is not a string"

private def digitsOf (fields : List (String × Json)) (key : String) : Except String String := do
  match ← field fields key with
  | .num text => .ok text
  | _ => .error s!"'{key}' is not a number"

private def attributes (fields : List (String × Json)) : Except String Attrs :=
  (fields.filter fun (key, _) => !reserved.contains key).mapM fun (key, json) =>
    return (key, ← attributeValue json)

private def spanOf (fields : List (String × Json)) : Except String Sdk.SpanData := do
  let start ← unixNano (← string fields Field.time)
  let kindText ← string fields Field.kind
  let some kind := kind? kindText | .error s!"'{kindText}' is not a span kind"
  let codeText ← digitsOf fields Field.statusCode
  let some status := codeText.toInt?.bind status? | .error s!"'{codeText}' is not a status"
  return {
    ctx := { traceId := ← string fields Field.traceId, spanId := ← string fields Field.spanId }
    parentSpanId := ← optional fields Field.parentId
    name := ← string fields Field.name
    kind, status
    startUnixNano := start
    endUnixNano := start + (← scaled 6 (← digitsOf fields Field.durationMs))
    attrs := ← attributes fields
    statusMessage := ← optional fields Field.statusMessage
  }

private def contextOf (fields : List (String × Json)) : Except String (Option SpanContext) := do
  match ← optional fields Field.traceId, ← optional fields Field.spanId with
  | none, none => .ok none
  | traceId, spanId => .ok (some { traceId := traceId.getD "", spanId := spanId.getD "" })

private def logOf (fields : List (String × Json)) : Except String LogRecord := do
  let codeText ← digitsOf fields Field.severityCode
  let some severity := codeText.toNat?.bind severity? | .error s!"'{codeText}' is not a severity"
  return {
    timeUnixNano := ← unixNano (← string fields Field.time)
    severity
    body := ← string fields Field.body
    attrs := ← attributes fields
    ctx := ← contextOf fields
  }

def row (json : Json) : Except String Row := do
  let .obj fields := json | .error "a row is a JSON object"
  let signal ← string fields Field.signalType
  if signal == logSignal then
    return .log (← logOf fields)
  else if signal == traceSignal then
    return .span (← spanOf fields)
  else
    .error s!"'{signal}' is not a signal this format carries"

def parse (line : String) : Except String Row := do
  row (← Json.parse line)

end Telemetry.Parse.Flat
