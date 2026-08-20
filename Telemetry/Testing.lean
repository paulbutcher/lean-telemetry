/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
module

public import Telemetry.Sdk.Exporter
public import Telemetry.Sdk.Install

/-!
# Testing instrumentation

An exporter that keeps what it is given, and a scoped way to install it, so that a test can
assert against the spans and log records an action emitted rather than against rendered output.

Installation is process-global: `hooksRef` and `Sdk.installation` are single `IO.Ref`s shared by
the whole process. So `capture` may not be used by tests running concurrently with each other,
nor concurrently with anything else that emits.
-/

public section

namespace Telemetry.Testing

open Telemetry.Sdk

/-- Keeps every span and log record handed to `Recorder.exporter`, and counts its shutdowns. -/
structure Recorder where
  spans : IO.Ref (Array SpanData)
  logs : IO.Ref (Array LogRecord)
  shutdowns : IO.Ref Nat

def Recorder.new : IO Recorder :=
  return { spans := ← IO.mkRef #[], logs := ← IO.mkRef #[], shutdowns := ← IO.mkRef 0 }

def Recorder.exporter (recorder : Recorder) : Exporter where
  exportSpans spans := recorder.spans.modify (· ++ spans)
  exportLogs logs := recorder.logs.modify (· ++ logs)
  shutdown := recorder.shutdowns.modify (· + 1)

/-- Everything one `Recorder` was given. Spans are in completion order, so a parent follows its
children. -/
structure Captured where
  spans : Array SpanData
  logs : Array LogRecord
  shutdowns : Nat
  deriving Repr, BEq, Inhabited

def Recorder.captured (recorder : Recorder) : IO Captured :=
  return {
    spans := ← recorder.spans.get
    logs := ← recorder.logs.get
    shutdowns := ← recorder.shutdowns.get
  }

/--
Puts both refs back as they were rather than calling `Sdk.shutdown`: an installation that was
merely displaced still belongs to whoever made it, and its exporters may not be shut down. The
hooks are restored directly, so that hooks installed by something other than the SDK survive too.
-/
private def restore (hooks : Option Hooks) (installed : Option Installation) : IO Unit := do
  Sdk.installation.set installed
  match hooks with
  | some hooks => installHooks hooks
  | none => clearHooks

/--
Runs `act` with a `Recorder` as the only exporter, and returns its result alongside everything
that reached the recorder. Whatever was installed beforehand, including nothing, is installed
again afterwards, on the exception path as well.

An exception from `act` propagates, which loses what was captured; a test that wants both should
catch inside `act` and return what it learned.
-/
def capture {α : Type} (act : IO α) : IO (α × Captured) := do
  let hooks ← currentHooks
  let installed ← Sdk.installation.get
  let recorder ← Recorder.new
  -- An exporter is never handed the resource, so there is nothing to put in this one.
  Sdk.install { attrs := [] } #[recorder.exporter]
  try
    let result ← act
    return (result, ← recorder.captured)
  finally
    restore hooks installed

end Telemetry.Testing
