/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
module

public import Telemetry.Context
public import Telemetry.Value

public section

namespace Telemetry

/-- `server` and `client` are set by instrumentation adapters, not by application code. -/
inductive SpanKind where
  | internal | server | client | producer | consumer
  deriving Repr, BEq, Inhabited

inductive StatusCode where
  | unset | ok | error
  deriving Repr, BEq, Inhabited

/--
The name is mutable because an HTTP server span cannot know the route it matched until the
router has run, and the route template is the name worth grouping by.
-/
structure ActiveSpan where
  ctx : SpanContext
  parentSpanId : Option String
  kind : SpanKind
  name : IO.Ref String
  attrs : IO.Ref Attrs
  status : IO.Ref (StatusCode × Option String)

/--
With no SDK installed there is nowhere to report to, so an inert span is handed to the action
instead: it absorbs every mutation, and needs no id, no clock read and no allocation.
-/
inductive Span where
  | inert
  | active (span : ActiveSpan)

def Span.context : Span → Option SpanContext
  | .inert => none
  | .active span => some span.ctx

def Span.add : Span → Attrs → IO Unit
  | .inert, _ => pure ()
  | .active span, attrs => span.attrs.modify (· ++ attrs)

def Span.rename : Span → String → IO Unit
  | .inert, _ => pure ()
  | .active span, name => span.name.set name

def Span.setStatus : Span → StatusCode → Option String → IO Unit
  | .inert, _, _ => pure ()
  | .active span, code, message => span.status.set (code, message)

end Telemetry
