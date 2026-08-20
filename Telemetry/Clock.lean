/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
module

import Std.Time

public section

namespace Telemetry.Clock

/-- Nanoseconds since the Unix epoch, for timestamps a backend will display. -/
def wallNanos : IO Nat := do
  let now ← Std.Time.Timestamp.now
  return now.toNanosecondsSinceUnixEpoch.val.toNat

/-- Nanoseconds from an arbitrary origin, for durations, which must not follow the wall clock. -/
def monoNanos : IO Nat := IO.monoNanosNow

end Telemetry.Clock
