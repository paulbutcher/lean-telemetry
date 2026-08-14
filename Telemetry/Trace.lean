/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Telemetry.Clock
import Telemetry.Hooks
import Telemetry.Id
import Telemetry.Monad

namespace Telemetry

private def openSpan (parent : Option SpanContext) (name : String) (kind : SpanKind)
    (attrs : Attrs) : IO ActiveSpan := do
  let ctx ← match parent with
    | some parent => parent.child
    | none => SpanContext.root
  return {
    ctx
    parentSpanId := parent.map (·.spanId)
    kind
    name := ← IO.mkRef name
    attrs := ← IO.mkRef attrs
    status := ← IO.mkRef (.unset, none)
  }

/--
Runs `act` under a new child of the current span, reporting the span when it returns. An
exception is reported too, with status `error` and the exception's message, and is then
re-raised unchanged: a failed operation is the one most worth finding afterwards.
-/
def span [Monad m] [MonadLiftT IO m] [MonadExceptOf IO.Error m] [MonadTelemetry m]
    (name : String) (act : Span → m α)
    (kind : SpanKind := .internal) (attrs : Attrs := []) : m α := do
  match ← currentHooks with
  | none => act .inert
  | some hooks =>
    let parent ← currentSpan
    let active ← openSpan parent name kind attrs
    let startUnixNano ← Clock.wallNanos
    let startMono ← Clock.monoNanos
    let report : IO Unit := do
      let elapsed := (← Clock.monoNanos) - startMono
      hooks.reportSpan active startUnixNano (startUnixNano + elapsed)
    tryCatchThe IO.Error
      (do
        let result ← withSpanContext (some active.ctx) (act (.active active))
        report
        return result)
      fun e => do
        Span.setStatus (.active active) .error (some (toString e))
        report
        throwThe IO.Error e

/-- `span` for actions with no interest in the span they are running under. -/
def spanning [Monad m] [MonadLiftT IO m] [MonadExceptOf IO.Error m] [MonadTelemetry m]
    (name : String) (act : m α)
    (kind : SpanKind := .internal) (attrs : Attrs := []) : m α :=
  span name (fun _ => act) kind attrs

end Telemetry
