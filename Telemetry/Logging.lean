/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Telemetry.Clock
import Telemetry.Hooks
import Telemetry.Monad
import Telemetry.Output
import Telemetry.Render

namespace Telemetry

/--
Unlike spans, log records are never dropped for want of an SDK: with none installed they go to
stdout and stderr in the readable format.
-/
def log [Monad m] [MonadLiftT IO m] [MonadTelemetry m]
    (severity : Severity) (body : String) (attrs : Attrs := []) : m Unit := do
  let ctx ← currentSpan
  let record : LogRecord :=
    { timeUnixNano := ← Clock.wallNanos, severity, body, attrs, ctx }
  match ← currentHooks with
  | some hooks => hooks.emitLog record
  | none => Output.line severity.isError (Render.logRecord record ++ "\n")

def trace [Monad m] [MonadLiftT IO m] [MonadTelemetry m]
    (body : String) (attrs : Attrs := []) : m Unit := log .trace body attrs

def debug [Monad m] [MonadLiftT IO m] [MonadTelemetry m]
    (body : String) (attrs : Attrs := []) : m Unit := log .debug body attrs

def info [Monad m] [MonadLiftT IO m] [MonadTelemetry m]
    (body : String) (attrs : Attrs := []) : m Unit := log .info body attrs

def warn [Monad m] [MonadLiftT IO m] [MonadTelemetry m]
    (body : String) (attrs : Attrs := []) : m Unit := log .warn body attrs

def error [Monad m] [MonadLiftT IO m] [MonadTelemetry m]
    (body : String) (attrs : Attrs := []) : m Unit := log .error body attrs

def fatal [Monad m] [MonadLiftT IO m] [MonadTelemetry m]
    (body : String) (attrs : Attrs := []) : m Unit := log .fatal body attrs

end Telemetry
