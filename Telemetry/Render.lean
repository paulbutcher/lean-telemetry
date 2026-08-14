/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Telemetry.Log

/-!
The readable format: aligned columns, one line per span or log record, shared by both so that a
developer watching a terminal reads a single stream.
-/

namespace Telemetry.Render

def pad (width : Nat) (s : String) : String :=
  if s.length ≥ width then s else s ++ "".pushn ' ' (width - s.length)

def padLeft (width : Nat) (s : String) : String :=
  if s.length ≥ width then s else "".pushn ' ' (width - s.length) ++ s

private def digits (width : Nat) (n : Nat) : String :=
  let s := toString n
  if s.length ≥ width then s else "".pushn '0' (width - s.length) ++ s

/-- Time of day in UTC; the record carries nanoseconds since the epoch and nothing else. -/
def timeOfDay (unixNanos : Nat) : String :=
  let millis := unixNanos / 1000000
  let secondOfDay := millis / 1000 % 86400
  let hours := secondOfDay / 3600
  let minutes := secondOfDay / 60 % 60
  s!"{digits 2 hours}:{digits 2 minutes}:{digits 2 (secondOfDay % 60)}.{digits 3 (millis % 1000)}"

def duration (nanos : Nat) : String :=
  let tenthsOfMilli := nanos / 100000
  s!"{tenthsOfMilli / 10}.{tenthsOfMilli % 10}ms"

def traceColumn : Option SpanContext → String
  | none => "--------"
  | some ctx => ctx.traceId.take 8 |>.toString

/-- One record is one line, so anything that would break the row is escaped, not passed on. -/
def escaped (s : String) : String :=
  s.replace "\\" "\\\\" |>.replace "\"" "\\\"" |>.replace "\n" "\\n"
    |>.replace "\r" "\\r" |>.replace "\t" "\\t"

private def quoted (s : String) : String :=
  "\"" ++ escaped s ++ "\""

def value : Value → String
  | .str v =>
    if v.isEmpty || v.any (fun c => c == ' ' || c == '"' || c == '=' || c.isWhitespace) then
      quoted v
    else
      escaped v
  | .int v => toString v
  | .bool v => toString v
  | .float v => toString v
  | .arr vs => "[" ++ String.intercalate "," (vs.map value) ++ "]"

def attrs (attrs : Attrs) : String :=
  String.intercalate " " (attrs.map fun (key, v) => s!"{escaped key}={value v}")

/--
One row of the readable format. `marker` is a duration for a span and a severity for a log
record, which keeps the two aligned in a shared stream.
-/
def line (timeUnixNano : Nat) (ctx : Option SpanContext) (marker subject : String)
    (attributes : Attrs) : String :=
  let head := s!"{timeOfDay timeUnixNano} {escaped (traceColumn ctx)} {padLeft 8 (escaped marker)}  "
  let subject := escaped subject
  if attributes.isEmpty then head ++ subject else s!"{head}{pad 18 subject} {attrs attributes}"

def logRecord (record : LogRecord) : String :=
  line record.timeUnixNano record.ctx record.severity.text record.body record.attrs

end Telemetry.Render
