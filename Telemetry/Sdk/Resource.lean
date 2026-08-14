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
In increasing order of precedence: what could be detected, then `OTEL_RESOURCE_ATTRIBUTES`,
then `OTEL_SERVICE_NAME`.
-/
def assemble (detected : Attrs) (attributes serviceName : Option String) : Resource :=
  let fromEnv := (attributes.map parseAttributes).getD []
  let service := (serviceName.map fun name => [(Conventions.serviceName, Value.str name)]).getD []
  { attrs := merge (merge detected fromEnv) service }

def detect : IO Resource :=
  return assemble (← detected) (← IO.getEnv "OTEL_RESOURCE_ATTRIBUTES")
    (← IO.getEnv "OTEL_SERVICE_NAME")

end Resource

end Telemetry.Sdk
