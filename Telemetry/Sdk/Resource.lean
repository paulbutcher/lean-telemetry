/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Telemetry

namespace Telemetry.Sdk

structure Resource where
  attrs : Attrs
  deriving Repr, BEq, Inhabited

namespace Resource

/-- Attributes from `upper` win, since they come from a more explicit source. -/
def merge (lower upper : Attrs) : Attrs :=
  lower.filter (fun (key, _) => !upper.any fun (other, _) => other == key) ++ upper

/-- Parses `OTEL_RESOURCE_ATTRIBUTES`: comma-separated `key=value` pairs. -/
def parseAttributes (spec : String) : Attrs :=
  spec.splitOn "," |>.filterMap fun pair =>
    match pair.splitOn "=" with
    | [] => none
    | [_] => none
    | key :: value =>
      let key := key.trimAscii.toString
      if key.isEmpty then none
      else some (key, .str (String.intercalate "=" value |>.trimAscii.toString))

def detected : IO Attrs := do
  let host := (← IO.getEnv "HOSTNAME").getD "unknown"
  return [(Conventions.hostName, .str host), (Conventions.processPid, .int (← IO.Process.getPID).toNat)]

/--
In increasing order of precedence: what could be detected, then `extra`, then
`OTEL_RESOURCE_ATTRIBUTES`, then `OTEL_SERVICE_NAME`.

`extra` sits below the environment so that an application can supply what the environment cannot
know, such as an identifier for an execution environment it is running in, without taking the
deployment's ability to override it.
-/
def assemble (detected : Attrs) (attributes serviceName : Option String)
    (extra : Attrs := []) : Resource :=
  let fromEnv := (attributes.map parseAttributes).getD []
  let service := (serviceName.map fun name => [(Conventions.serviceName, Value.str name)]).getD []
  { attrs := merge (merge (merge detected extra) fromEnv) service }

def detect (extra : Attrs := []) : IO Resource :=
  return assemble (← detected) (← IO.getEnv "OTEL_RESOURCE_ATTRIBUTES")
    (← IO.getEnv "OTEL_SERVICE_NAME") extra

end Resource

end Telemetry.Sdk
