/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
module

/-!
Just enough JSON to write OTLP payloads. Lean's `Json` lives in the `Lean` library rather than
in `Std`, and this library will not take the compiler as a dependency for one encoder.
-/

public section

namespace Telemetry.Sdk.Json

inductive Json where
  | str (v : String)
  | num (v : Int)
  /-- A number carried as the digits already written for it, for a value whose exactness
  matters: `num` holds no fraction and `float` would round one. -/
  | decimal (digits : String)
  | float (v : Float)
  | bool (v : Bool)
  | arr (items : List Json)
  | obj (fields : List (String × Json))
  deriving Inhabited

private def hex4 (n : Nat) : String :=
  let digit (d : Nat) : Char :=
    if d < 10 then Char.ofNat ('0'.toNat + d) else Char.ofNat ('a'.toNat + d - 10)
  String.ofList [digit (n / 4096 % 16), digit (n / 256 % 16), digit (n / 16 % 16), digit (n % 16)]

def escape (s : String) : String :=
  s.foldl (init := "") fun acc c =>
    match c with
    | '"' => acc ++ "\\\""
    | '\\' => acc ++ "\\\\"
    | '\n' => acc ++ "\\n"
    | '\r' => acc ++ "\\r"
    | '\t' => acc ++ "\\t"
    | c => if c.toNat < 0x20 then acc ++ "\\u" ++ hex4 c.toNat else acc.push c

mutual

def render : Json → String
  | .str v => "\"" ++ escape v ++ "\""
  | .num v => toString v
  | .decimal digits => digits
  | .float v => toString v
  | .bool v => if v then "true" else "false"
  | .arr items => "[" ++ renderItems items ++ "]"
  | .obj fields => "{" ++ renderFields fields ++ "}"

def renderItems : List Json → String
  | [] => ""
  | [item] => render item
  | item :: rest => render item ++ "," ++ renderItems rest

def renderFields : List (String × Json) → String
  | [] => ""
  | [(key, v)] => "\"" ++ escape key ++ "\":" ++ render v
  | (key, v) :: rest => "\"" ++ escape key ++ "\":" ++ render v ++ "," ++ renderFields rest

end

end Telemetry.Sdk.Json
