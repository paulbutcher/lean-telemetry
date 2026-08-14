/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Telemetry.Value

/-!
These check that the coercions make call sites elaborate without ceremony, which is the whole
point of them, and that each one lands on the constructor it claims.
-/

namespace TelemetryTest.Value

open Telemetry

example : Attrs :=
  [("db.system.name", "postgresql"),
   ("http.response.status_code", 200),
   ("http.request.resend_count", (3 : Nat)),
   ("error", true),
   ("sampling.ratio", 0.25),
   ("http.request.header.accept", .arr ["text/html", "text/plain"])]

#guard (("k", 200) : String × Value).2 == Value.int 200
#guard ((0.5 : Value)) == Value.float 0.5
#guard (("k", (-7 : Int)) : String × Value).2 == Value.int (-7)

end TelemetryTest.Value
