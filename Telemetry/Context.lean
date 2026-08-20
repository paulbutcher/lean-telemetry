/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
module

public section

namespace Telemetry

/--
Identifies a span, in the W3C trace context widths: `traceId` is 32 lowercase hex characters
and `spanId` is 16.

`TypeName` is derived because downstream packages store a `SpanContext` in typed extension
maps.
-/
structure SpanContext where
  traceId : String
  spanId : String
  deriving TypeName, Inhabited, BEq, Repr

end Telemetry
