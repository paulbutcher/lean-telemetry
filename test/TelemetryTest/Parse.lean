/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
module

public import Telemetry.Parse.Json
public import Telemetry.Sdk.Json
public import TelemetryTest.Harness

public section

namespace TelemetryTest.Parse

private def read (s : String) : Option Telemetry.Parse.Json :=
  (Telemetry.Parse.Json.parse s).toOption

private def failed (s : String) : Bool := (Telemetry.Parse.Json.parse s).toOption.isNone

/-- The pair of escaping and unescaping is where a reader and a writer most easily disagree, and
neither one alone says what a string should come back as. -/
private def survives (s : String) : Bool :=
  read (Telemetry.Sdk.Json.render (.str s)) == some (.str s)

def suite : TestM Unit := do
  checkEq "an object keeps its members in order"
    (read "{\"b\":1,\"a\":true}")
    (some (.obj [("b", .num "1"), ("a", .bool true)]))
  checkEq "whitespace between tokens is ignored"
    (read " {\n\t\"a\" : [ 1 , null ]\n} ") (some (.obj [("a", .arr [.num "1", .null])]))
  checkEq "an empty object and an empty array are values"
    (read "[{},[]]") (some (.arr [.obj [], .arr []]))

  -- The point of keeping the digits: this one is past what a double holds exactly.
  checkEq "a number keeps the digits it was written with"
    (read "1755172471882000000") (some (.num "1755172471882000000"))
  checkEq "and so does a fraction" (read "8.123456") (some (.num "8.123456"))

  checkEq "a surrogate pair is one character"
    (read "\"\\ud83d\\ude00\"") (some (.str "😀"))
  checkEq "the short escapes are read"
    (read "\"a\\\"b\\\\c\\n\\u0041\"") (some (.str "a\"b\\c\nA"))

  check "an unterminated string is refused" (failed "\"abc")
  check "a lone surrogate is refused rather than becoming some other character"
    (failed "\"\\ud83d\"")
  check "a second value after the first is refused" (failed "{} {}")
  check "an unclosed object is refused" (failed "{\"a\":1")
  check "a member without a name is refused" (failed "{1:2}")

  property "a string survives being written and read back" (∀ s : String, survives s)

end TelemetryTest.Parse
