/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Plausible

namespace TelemetryTest

abbrev TestM := StateT (Array String) IO

def failure (message : String) : TestM Unit :=
  modify (·.push message)

def containsText (haystack needle : String) : Bool :=
  (haystack.splitOn needle).length > 1

def check (label : String) (cond : Bool) : TestM Unit :=
  unless cond do failure label

def checkEq [BEq α] [Repr α] (label : String) (actual expected : α) : TestM Unit :=
  unless actual == expected do
    failure s!"{label}: expected {repr expected}, got {repr actual}"

open Plausible Plausible.Decorations in
/--
Runs a Plausible property as an ordinary check. The `plausible` tactic proves goals by
admitting them, which a build that treats warnings as errors will not accept, so properties
are run here at test time instead.
-/
def property (label : String) (p : Prop)
    (p' : Decorations.DecorationsOf p := by mk_decorations) [Testable p']
    (cfg : Configuration := {}) : TestM Unit := do
  match ← Testable.checkIO p' { cfg with quiet := true } with
  | .success _ => pure ()
  | .gaveUp n => failure s!"{label}: gave up after {n} discarded samples"
  | .failure _ counterExample shrinks =>
    failure s!"{label}: counter-example after {shrinks} shrinks: {String.intercalate ", " counterExample}"

def runSuite (name : String) (suite : TestM Unit) : IO Nat := do
  let (_, failures) ← suite.run #[]
  if failures.isEmpty then
    IO.println s!"ok   {name}"
  else
    IO.println s!"FAIL {name}"
    for f in failures do
      IO.println s!"       {f}"
  return failures.size

def runAll (suites : List (String × TestM Unit)) : IO UInt32 := do
  let mut failed := 0
  for (name, suite) in suites do
    failed := failed + (← runSuite name suite)
  if failed == 0 then
    return 0
  IO.eprintln s!"{failed} check(s) failed"
  return 1

end TelemetryTest
