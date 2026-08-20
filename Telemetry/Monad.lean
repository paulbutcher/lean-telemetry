/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
module

public import Telemetry.Context

public section

namespace Telemetry

/-- The current span, carried in the monad rather than passed as a parameter. -/
class MonadTelemetry (m : Type → Type) where
  currentSpan : m (Option SpanContext)
  withSpanContext {α : Type} : Option SpanContext → m α → m α

export MonadTelemetry (currentSpan withSpanContext)

abbrev TelemetryT := ReaderT (Option SpanContext)

/-- Runs an action with no span in scope, so that the spans it opens are roots. -/
def runTelemetry [Monad m] (act : TelemetryT m α) : m α :=
  act.run none

instance (priority := low) [MonadTelemetry m] : MonadTelemetry (ReaderT ρ m) where
  currentSpan := fun _ => currentSpan
  withSpanContext ctx act := fun r => withSpanContext ctx (act r)

instance (priority := low) [Functor m] [MonadTelemetry m] : MonadTelemetry (StateT σ m) where
  currentSpan := fun s => (·, s) <$> currentSpan
  withSpanContext ctx act := fun s => withSpanContext ctx (act s)

instance (priority := low) [Monad m] [MonadTelemetry m] : MonadTelemetry (ExceptT ε m) where
  currentSpan := ExceptT.lift currentSpan
  withSpanContext ctx act := ExceptT.mk (withSpanContext ctx act.run)

instance [Monad m] : MonadTelemetry (TelemetryT m) where
  currentSpan := readThe (Option SpanContext)
  withSpanContext ctx act := withTheReader (Option SpanContext) (fun _ => ctx) act

end Telemetry
