/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
module

public import Telemetry.Sdk.Exporter
public import Telemetry.Sdk.Otlp

public section

namespace Telemetry.Sdk.Console

/-- The status message earns a column of its own, since it is what the reader is looking for. -/
def renderSpan (span : SpanData) : String :=
  let failure :=
    if span.status == .error then [("ERROR", Value.str (span.statusMessage.getD ""))] else []
  Render.line span.startUnixNano (some span.ctx) (Render.duration span.durationNanos) span.name
    (span.attrs ++ failure)

/-- One readable line per span and per log record. Spans are always ordinary output. -/
def pretty : Exporter where
  exportSpans spans := spans.forM fun span => Output.stdout (renderSpan span ++ "\n")
  exportLogs records := records.forM fun record =>
    Output.line record.severity.isError (Render.logRecord record ++ "\n")

/--
OTLP/JSON on stdout, one request per line. Choosing this format gives the stream over to the
machine, so the readable format is simply unavailable there.
-/
def otlpJson (resource : Resource) : Exporter where
  exportSpans spans := Output.stdout (Otlp.traceRequest resource spans ++ "\n")
  exportLogs records := Output.stdout (Otlp.logsRequest resource records ++ "\n")

end Telemetry.Sdk.Console
