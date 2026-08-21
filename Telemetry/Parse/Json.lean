/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
module

/-!
A JSON reader, kept apart from the writer so that a process which only ever emits telemetry
carries none of it.

Numbers are kept as the digits they were written with rather than as a `Float`: a time or a
duration in the flat format is past the range a double represents exactly, so nothing may be
recovered by way of one.
-/

public section

namespace Telemetry.Parse

inductive Json where
  | null
  | str (v : String)
  | num (text : String)
  | bool (v : Bool)
  | arr (items : List Json)
  | obj (fields : List (String × Json))
  deriving Repr, BEq, Inhabited

namespace Json

private inductive Token where
  | lbrace | rbrace | lbracket | rbracket | colon | comma
  | null | str (v : String) | num (text : String) | bool (v : Bool)
  deriving Repr, BEq, Inhabited

private def hexValue (c : Char) : Option Nat :=
  if c.isDigit then some (c.toNat - '0'.toNat)
  else if 'a' ≤ c && c ≤ 'f' then some (c.toNat - 'a'.toNat + 10)
  else if 'A' ≤ c && c ≤ 'F' then some (c.toNat - 'A'.toNat + 10)
  else none

private def hex4 (a b c d : Char) : Option Nat := do
  return (((← hexValue a) * 16 + (← hexValue b)) * 16 + (← hexValue c)) * 16 + (← hexValue d)

private def leadingSurrogate (n : Nat) : Bool := 0xd800 ≤ n && n ≤ 0xdbff

private def trailingSurrogate (n : Nat) : Bool := 0xdc00 ≤ n && n ≤ 0xdfff

private def escapeError : String := "a \\u escape needs four hexadecimal digits"

private def surrogateError : String := "a leading surrogate needs a trailing one after it"

/-- A surrogate pair is one character, so the two escapes are consumed together; on their own
neither half is a character at all. -/
private def scanString (acc : String) : List Char → Except String (String × List Char)
  | [] => .error "a string was not terminated"
  | '"' :: rest => .ok (acc, rest)
  | '\\' :: 'u' :: a :: b :: c :: d :: rest =>
    match hex4 a b c d with
    | none => .error escapeError
    | some n =>
      if leadingSurrogate n then
        match rest with
        | '\\' :: 'u' :: e :: f :: g :: h :: rest =>
          match hex4 e f g h with
          | none => .error escapeError
          | some low =>
            if trailingSurrogate low then
              scanString (acc.push (Char.ofNat (0x10000 + (n - 0xd800) * 1024 + (low - 0xdc00)))) rest
            else
              .error surrogateError
        | _ => .error surrogateError
      else if trailingSurrogate n then
        .error "a trailing surrogate stands on its own"
      else
        scanString (acc.push (Char.ofNat n)) rest
  | '\\' :: c :: rest =>
    match c with
    | '"' => scanString (acc.push '"') rest
    | '\\' => scanString (acc.push '\\') rest
    | '/' => scanString (acc.push '/') rest
    | 'b' => scanString (acc.push (Char.ofNat 8)) rest
    | 'f' => scanString (acc.push (Char.ofNat 12)) rest
    | 'n' => scanString (acc.push '\n') rest
    | 'r' => scanString (acc.push '\r') rest
    | 't' => scanString (acc.push '\t') rest
    | c => .error s!"'\\{c}' is not an escape"
  | c :: rest => scanString (acc.push c) rest

private def isNumberChar (c : Char) : Bool :=
  c.isDigit || c == '-' || c == '+' || c == '.' || c == 'e' || c == 'E'

private def scanNumber (acc : String) : List Char → String × List Char
  | c :: rest => if isNumberChar c then scanNumber (acc.push c) rest else (acc, c :: rest)
  | [] => (acc, [])

/--
`fuel` starts at the number of characters and every step below consumes at least one of them, so
the exhausted case cannot be reached; a total function needs it all the same.
-/
private def tokenise : Nat → Array Token → List Char → Except String (Array Token)
  | _, acc, [] => .ok acc
  | 0, _, _ => .error "the reader ran out of steps"
  | fuel + 1, acc, c :: rest =>
    match c with
    | '{' => tokenise fuel (acc.push .lbrace) rest
    | '}' => tokenise fuel (acc.push .rbrace) rest
    | '[' => tokenise fuel (acc.push .lbracket) rest
    | ']' => tokenise fuel (acc.push .rbracket) rest
    | ':' => tokenise fuel (acc.push .colon) rest
    | ',' => tokenise fuel (acc.push .comma) rest
    | '"' => do
      let (v, rest) ← scanString "" rest
      tokenise fuel (acc.push (.str v)) rest
    | 't' =>
      match rest with
      | 'r' :: 'u' :: 'e' :: rest => tokenise fuel (acc.push (.bool true)) rest
      | _ => .error "'true' was expected"
    | 'f' =>
      match rest with
      | 'a' :: 'l' :: 's' :: 'e' :: rest => tokenise fuel (acc.push (.bool false)) rest
      | _ => .error "'false' was expected"
    | 'n' =>
      match rest with
      | 'u' :: 'l' :: 'l' :: rest => tokenise fuel (acc.push .null) rest
      | _ => .error "'null' was expected"
    | c =>
      if c.isWhitespace then
        tokenise fuel acc rest
      else if isNumberChar c then
        let (text, rest) := scanNumber "" (c :: rest)
        tokenise fuel (acc.push (.num text)) rest
      else
        .error s!"'{c}' cannot start a value"

private def valueExpected : String := "a value was expected"

-- `fuel` bounds the descent: every step either consumes a token or descends into one just
-- consumed, so twice the token count more than covers it.
mutual

private def value (fuel : Nat) (ts : List Token) : Except String (Json × List Token) :=
  match fuel, ts with
  | 0, _ => .error valueExpected
  | _, [] => .error valueExpected
  | fuel + 1, t :: rest =>
    match t with
    | .null => .ok (.null, rest)
    | .str v => .ok (.str v, rest)
    | .num text => .ok (.num text, rest)
    | .bool v => .ok (.bool v, rest)
    | .lbracket => elements fuel #[] rest
    | .lbrace => members fuel #[] rest
    | _ => .error valueExpected

private def elements (fuel : Nat) (acc : Array Json) (ts : List Token) :
    Except String (Json × List Token) :=
  match fuel, ts with
  | 0, _ => .error valueExpected
  | _, .rbracket :: rest => .ok (.arr acc.toList, rest)
  | fuel + 1, ts => do
    let (item, ts) ← value fuel ts
    match ts with
    | .comma :: ts => elements fuel (acc.push item) ts
    | .rbracket :: rest => .ok (.arr (acc.push item).toList, rest)
    | _ => .error "',' or ']' was expected"

private def members (fuel : Nat) (acc : Array (String × Json)) (ts : List Token) :
    Except String (Json × List Token) :=
  match fuel, ts with
  | 0, _ => .error valueExpected
  | _, .rbrace :: rest => .ok (.obj acc.toList, rest)
  | fuel + 1, .str key :: .colon :: ts => do
    let (v, ts) ← value fuel ts
    match ts with
    | .comma :: ts => members fuel (acc.push (key, v)) ts
    | .rbrace :: rest => .ok (.obj (acc.push (key, v)).toList, rest)
    | _ => .error "',' or '}' was expected"
  | _, _ => .error "a member name was expected"

end

def parse (s : String) : Except String Json := do
  let cs := s.toList
  let ts := (← tokenise cs.length #[] cs).toList
  let (json, rest) ← value (2 * ts.length + 2) ts
  if rest.isEmpty then .ok json else .error "a second value follows the first"

end Json

end Telemetry.Parse
