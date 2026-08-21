/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Lake
open Lake DSL

/-- Bumping `version` also means bumping `Otlp.libraryVersion`, which reports it on the wire. -/
package telemetry where
  version := v!"0.4.0"
  leanOptions := #[⟨`warningAsError, true⟩]

require leancurl from git "https://github.com/paulbutcher/leancurl" @ "v0.3.0"

@[default_target]
lean_lib Telemetry

@[default_target]
lean_lib TelemetrySdk where
  roots := #[`Telemetry.Sdk]

/-- Reading the flat format back. Nothing that only writes telemetry need import it, which is
why the reader is not part of `TelemetrySdk`. -/
@[default_target]
lean_lib TelemetryParse where
  roots := #[`Telemetry.Parse]

/-- For a consumer's test code; nothing in an application need import it. -/
@[default_target]
lean_lib TelemetryTesting where
  roots := #[`Telemetry.Testing]

/-- Keeps the tests and their dependencies out of the graph a consumer resolves. -/
@[test_driver]
script tests do
  let child ← IO.Process.spawn
    { cmd := "lake", args := #["test"], cwd := __dir__ / "test" }
  child.wait
