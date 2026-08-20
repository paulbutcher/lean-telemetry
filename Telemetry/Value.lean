/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
module

public section

namespace Telemetry

/--
The values an attribute may take, mirroring OTLP's `AnyValue`. There is no decimal case:
OTLP has none, so durations travel as start and end timestamps rather than as a
pre-computed attribute.
-/
inductive Value where
  | str (v : String)
  | int (v : Int)
  | bool (v : Bool)
  | float (v : Float)
  | arr (vs : List Value)
  deriving Repr, BEq, Inhabited

abbrev Attrs := List (String × Value)

instance : Coe String Value := ⟨.str⟩
instance : Coe Int Value := ⟨.int⟩
instance : Coe Nat Value := ⟨fun n => .int n⟩
instance : Coe Bool Value := ⟨.bool⟩
instance : Coe Float Value := ⟨.float⟩
instance : Coe (List Value) Value := ⟨.arr⟩

instance : OfNat Value n := ⟨.int n⟩
instance : OfScientific Value := ⟨fun m e d => .float (OfScientific.ofScientific m e d)⟩

end Telemetry
