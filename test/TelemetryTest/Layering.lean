/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import TelemetryTest.Harness

/-!
The API library must stay a strict leaf: nothing under `Telemetry/` other than the SDK and the
testing library may import the SDK, and nothing but the testing library may import the testing
library, or an application would acquire a dependency on it. Lake cannot express either
constraint, so they are checked here.
-/

namespace TelemetryTest.Layering

def imports (source : String) (module : String) : Bool :=
  source.splitOn "\n" |>.any fun line =>
    let line := line.trimAscii.toString
    line == s!"import {module}" || line.startsWith s!"import {module}."

def isSdkSource (path : System.FilePath) : Bool :=
  let path := path.toString
  containsText path "Telemetry/Sdk." || containsText path "Telemetry/Sdk/"

def isTestingSource (path : System.FilePath) : Bool :=
  containsText path.toString "Telemetry/Testing."

/-- These tests are their own package, so the sources they scan sit one level above them. -/
def sourceRoot : System.FilePath := ".."

def librarySources : IO (Array System.FilePath) := do
  let all ← System.FilePath.walkDir (sourceRoot / "Telemetry")
  let lean := all.filter fun p => p.extension == some "lean"
  return lean.push (sourceRoot / "Telemetry.lean")

def suite : TestM Unit := do
  let sources ← librarySources
  check "scanned at least the API root" (sources.size ≥ 1)
  check "scanned the testing library" (sources.any isTestingSource)
  for source in sources do
    let contents ← IO.FS.readFile source
    unless isSdkSource source || isTestingSource source do
      check s!"{source} does not import the SDK" (!imports contents "Telemetry.Sdk")
    unless isTestingSource source do
      check s!"{source} does not import the testing library"
        (!imports contents "Telemetry.Testing")

end TelemetryTest.Layering
