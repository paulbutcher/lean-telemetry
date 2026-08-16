/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import TelemetryTest.Harness

/-!
The API library must stay a strict leaf: nothing under `Telemetry/` other than the SDK may
import the SDK. Lake cannot express that constraint, so it is checked here.
-/

namespace TelemetryTest.Layering

def importsSdk (source : String) : Bool :=
  source.splitOn "\n" |>.any fun line =>
    let line := line.trimAscii.toString
    line == "import Telemetry.Sdk" || line.startsWith "import Telemetry.Sdk."

def isSdkSource (path : System.FilePath) : Bool :=
  let path := path.toString
  containsText path "Telemetry/Sdk." || containsText path "Telemetry/Sdk/"

/-- These tests are their own package, so the sources they scan sit one level above them. -/
def sourceRoot : System.FilePath := ".."

def apiSources : IO (Array System.FilePath) := do
  let all ← System.FilePath.walkDir (sourceRoot / "Telemetry")
  let api := all.filter fun p => p.extension == some "lean" && !isSdkSource p
  return api.push (sourceRoot / "Telemetry.lean")

def suite : TestM Unit := do
  let sources ← apiSources
  check "scanned at least the API root" (sources.size ≥ 1)
  for source in sources do
    let contents ← IO.FS.readFile source
    check s!"{source} does not import the SDK" (!importsSdk contents)

end TelemetryTest.Layering
