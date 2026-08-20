/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
module

public import Telemetry.Log
public import Telemetry.Span

public section

namespace Telemetry

/--
The seam between the API and the SDK. The API may not name the SDK's types, so the SDK installs
closures here instead, and `span` treats their absence as "no SDK, do nothing".
-/
structure Hooks where
  reportSpan : ActiveSpan → (startUnixNano : Nat) → (endUnixNano : Nat) → IO Unit
  emitLog : LogRecord → IO Unit

initialize hooksRef : IO.Ref (Option Hooks) ← IO.mkRef none

def installHooks (hooks : Hooks) : IO Unit :=
  hooksRef.set (some hooks)

def clearHooks : IO Unit :=
  hooksRef.set none

def currentHooks : IO (Option Hooks) :=
  hooksRef.get

end Telemetry
