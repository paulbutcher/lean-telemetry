/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
module

public import TelemetryTest.Harness

/-!
The API library must stay a strict leaf: nothing under `Telemetry/` other than the SDK and the
testing library may import the SDK, and nothing but the testing library may import the testing
library, or an application would acquire a dependency on it. Lake cannot express either
constraint, so they are checked here.
-/

public section

namespace TelemetryTest.Layering

private def importKeywords : List String :=
  ["import", "public import", "meta import", "public meta import"]

def imports (source : String) (module : String) : Bool :=
  source.splitOn "\n" |>.any fun line =>
    let line := line.trimAscii.toString
    importKeywords.any fun keyword =>
      line == s!"{keyword} {module}" || line.startsWith s!"{keyword} {module}."

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
  let mut recognised := false
  for source in sources do
    let contents ← IO.FS.readFile source
    if isTestingSource source then
      recognised := recognised || imports contents "Telemetry.Sdk"
    else
      unless isSdkSource source do
        check s!"{source} does not import the SDK" (!imports contents "Telemetry.Sdk")
      check s!"{source} does not import the testing library"
        (!imports contents "Telemetry.Testing")
  -- Every check above is satisfied by an `imports` that recognises nothing at all, so the
  -- one import known to be there has to be found for the rest to mean anything.
  check "the scan recognises an import" recognised

end TelemetryTest.Layering
