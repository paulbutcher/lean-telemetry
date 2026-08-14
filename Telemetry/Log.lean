/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Telemetry.Context
import Telemetry.Value

namespace Telemetry

inductive Severity where
  | trace | debug | info | warn | error | fatal
  deriving Repr, BEq, Inhabited, DecidableEq

/-- The OTLP severity numbers; the range between them is left for finer gradations. -/
def Severity.number : Severity → Nat
  | .trace => 1
  | .debug => 5
  | .info => 9
  | .warn => 13
  | .error => 17
  | .fatal => 21

def Severity.text : Severity → String
  | .trace => "TRACE"
  | .debug => "DEBUG"
  | .info => "INFO"
  | .warn => "WARN"
  | .error => "ERROR"
  | .fatal => "FATAL"

/-- Records at `error` and above go to stderr; everything else goes to stdout. -/
def Severity.isError (s : Severity) : Bool :=
  s.number ≥ Severity.error.number

/--
A log record emitted inside a span carries that span's context, which is why logging belongs
in this library rather than alongside it.
-/
structure LogRecord where
  timeUnixNano : Nat
  severity : Severity
  body : String
  attrs : Attrs := []
  ctx : Option SpanContext := none
  deriving Repr, BEq, Inhabited

end Telemetry
