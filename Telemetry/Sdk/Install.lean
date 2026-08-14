/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Telemetry.Sdk.Config
import Telemetry.Sdk.Console
import Telemetry.Sdk.Resource

namespace Telemetry.Sdk

structure Installation where
  resource : Resource
  exporters : Array Exporter

initialize installation : IO.Ref (Option Installation) ← IO.mkRef none

/-- Every exporter sees every span and every log record; this is how one process can serve both
a human watching a terminal and a collector. -/
def install (resource : Resource) (exporters : Array Exporter) : IO Unit := do
  installation.set (some { resource, exporters })
  installHooks {
    reportSpan := fun span startUnixNano endUnixNano => do
      let data ← SpanData.ofSpan span startUnixNano endUnixNano
      exporters.forM (·.exportSpans #[data])
    emitLog := fun record => exporters.forM (·.exportLogs #[record])
  }

def shutdown : IO Unit := do
  clearHooks
  if let some installed ← installation.get then
    installed.exporters.forM (·.shutdown)
  installation.set none

/-- Nothing is buffered, so there is nothing to flush; applications should still call it. -/
def flush : IO Unit := pure ()

private def onlySignals (exporter : Exporter) (spans logs : Bool) : Exporter :=
  { exporter with
    exportSpans := if spans then exporter.exportSpans else fun _ => pure ()
    exportLogs := if logs then exporter.exportLogs else fun _ => pure () }

private def build (resource : Resource) (config : Config) (kind : ExporterKind) : IO Exporter :=
  match kind with
  | .console =>
    match config.consoleFormat with
    | .pretty => pure Console.pretty
    | .otlpJson => pure (Console.otlpJson resource)
  | .file => File.otlpJson resource config.file

def installFromEnv : IO Unit := do
  let (config, warnings) ← Config.fromEnv
  for warning in warnings do
    Output.stderr s!"lean-telemetry: {warning}\n"
  if config.disabled then
    return
  let resource ← Resource.detect
  -- One exporter per kind even when both signals want it, so that both share its stream.
  let kinds := (config.traces ++ config.logs).eraseDups
  let exporters ← kinds.toArray.mapM fun kind => do
    let exporter ← build resource config kind
    return onlySignals exporter (config.traces.contains kind) (config.logs.contains kind)
  if exporters.isEmpty then
    return
  install resource exporters

end Telemetry.Sdk
