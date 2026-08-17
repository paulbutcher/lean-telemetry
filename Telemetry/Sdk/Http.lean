/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Leancurl
import Std.Sync.Mutex
import Telemetry.Sdk.Exporter
import Telemetry.Sdk.Otlp

/-!
OTLP/JSON over HTTP, for handing off to a collector in the same execution environment where that
collector cannot read files. The traffic is not expected to leave the machine, which is what
allows TLS, authentication, retry and queueing to be left out: once the collector has the data it
owns delivery, and everything before that is a loopback socket.
-/

namespace Telemetry.Sdk.Http

def defaultEndpoint : String := "http://localhost:4318"

def defaultTimeoutMillis : Nat := 10000

def tracesPath : String := "/v1/traces"

def logsPath : String := "/v1/logs"

structure Config where
  traces : String
  logs : String
  timeoutMillis : Nat
  deriving Repr, BEq

/-- Appends a signal's path to a base endpoint, whether or not the base ends in a separator. -/
def signalUrl (base path : String) : String :=
  (base.dropEndWhile (· == '/')).toString ++ path

/--
A base endpoint carries the signal's path; a per-signal endpoint is a complete URL and is used
exactly as given.
-/
def resolve (base traces logs : Option String) (timeoutMillis : Nat) : Config :=
  let root := base.getD defaultEndpoint
  { traces := traces.getD (signalUrl root tracesPath)
    logs := logs.getD (signalUrl root logsPath)
    timeoutMillis }

def default : Config := resolve none none none defaultTimeoutMillis

/--
A collector that is slow to start, has crashed, or was never deployed must cost the application
one line of stderr, not one per span, so failures are reported when they begin and counted after
that.
-/
private structure Failures where
  reported : Bool := false
  dropped : Nat := 0

private def announce (message : String) : IO Unit :=
  Output.stderr s!"lean-telemetry: {message}\n"

private def recordFailure (state : Std.Mutex Failures) (reason : String) : IO Unit := do
  let first ← state.atomically do
    let failures ← get
    set ({ reported := true, dropped := failures.dropped + 1 } : Failures)
    return !failures.reported
  if first then
    announce s!"{reason}; further export failures will be counted rather than reported"

private def recordSuccess (state : Std.Mutex Failures) : IO Unit := do
  let dropped ← state.atomically do
    let failures ← get
    if failures.reported then
      set ({} : Failures)
      return failures.dropped
    else
      return 0
  if dropped > 0 then
    announce s!"collector reachable again; {dropped} export(s) were dropped"

/--
Delivery is best-effort in the strongest sense: nothing here propagates, because an application
must not see a request fail because telemetry could not be delivered.
-/
private def post (config : Config) (state : Std.Mutex Failures) (url body : String) : IO Unit := do
  let request : Leancurl.Request := {
    url
    method := .post
    headers := [("Content-Type", "application/json")]
    body := some body.toUTF8
    timeoutMs := some config.timeoutMillis.toUInt32
    followRedirects := false
  }
  match ← (Leancurl.Curl.send request).toBaseIO with
  | .error e => recordFailure state s!"{url}: {e}"
  | .ok (.error e) => recordFailure state s!"{url}: {e.message}"
  | .ok (.ok response) =>
    if 200 ≤ response.status && response.status < 300 then
      recordSuccess state
    else
      recordFailure state s!"{url}: collector answered {response.status}"

/--
Nothing is opened here, so a collector that is not yet listening does not stop an application
starting. Each export is its own connection: an execution environment that freezes between
invocations freezes both ends of a kept one, and it would be resumed against a peer that may
long since have dropped it.
-/
def otlpJson (resource : Resource) (config : Config) : IO Exporter := do
  let state ← Std.Mutex.new ({} : Failures)
  return {
    exportSpans := fun spans => post config state config.traces (Otlp.traceRequest resource spans)
    exportLogs := fun records => post config state config.logs (Otlp.logsRequest resource records)
  }

end Telemetry.Sdk.Http
