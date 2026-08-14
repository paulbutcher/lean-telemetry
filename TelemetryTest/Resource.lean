/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Telemetry.Sdk.Resource
import TelemetryTest.Harness

namespace TelemetryTest.Resource

open Telemetry Telemetry.Sdk Telemetry.Sdk.Resource

private def detected : Attrs :=
  [(Conventions.hostName, .str "box"), (Conventions.serviceName, .str "detected")]

def suite : TestM Unit := do
  checkEq "pairs are split on the first equals sign"
    (parseAttributes "deployment.environment=staging,url=https://x/?a=b")
    [("deployment.environment", .str "staging"), ("url", .str "https://x/?a=b")]
  checkEq "surrounding space is not part of the key or value"
    (parseAttributes " a = 1 ") [("a", .str "1")]
  checkEq "pairs that are not pairs are dropped"
    (parseAttributes "novalue,=nokey,a=1") [("a", .str "1")]

  checkEq "the more explicit source wins"
    (merge [("a", .str "low"), ("b", .str "low")] [("a", .str "high")])
    [("b", .str "low"), ("a", .str "high")]

  let assembled := assemble detected (some "service.name=fromAttributes,extra=1") none
  checkEq "OTEL_RESOURCE_ATTRIBUTES beats what was detected"
    (assembled.attrs.lookup Conventions.serviceName) (some (.str "fromAttributes"))
  let named := assemble detected (some "service.name=fromAttributes") (some "fromServiceName")
  checkEq "OTEL_SERVICE_NAME beats OTEL_RESOURCE_ATTRIBUTES"
    (named.attrs.lookup Conventions.serviceName) (some (.str "fromServiceName"))
  checkEq "detected attributes survive alongside" (named.attrs.lookup Conventions.hostName)
    (some (.str "box"))

  let host := (← Telemetry.Sdk.Resource.detect).attrs.lookup Conventions.hostName
  check "a host name is always reported" host.isSome

end TelemetryTest.Resource
