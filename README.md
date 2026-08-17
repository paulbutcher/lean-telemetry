# lean-telemetry

OpenTelemetry tracing and logging for Lean 4 applications.

It produces spans and log records and writes them either in a readable form for a developer
watching a terminal, or as OTLP/JSON for an OpenTelemetry Collector to forward to a backend.

It speaks no HTTP. There is no network code, no FFI and no vendor-specific code anywhere in it:
telemetry leaves the process on stdout, on stderr, or in files on disk, and getting it from
there to a backend is the collector's job.

## Libraries

| Library | Contents | Depends on |
|---|---|---|
| `Telemetry` | The API: `MonadTelemetry`, `span`, `spanning`, the log functions, semantic convention constants. | Lean core and Std only |
| `Telemetry.Sdk` | Resource detection, exporters, installation, configuration from the environment. | `Telemetry` |
| `Telemetry.Testing` | Test helpers. | `Telemetry.Sdk` |

Instrument a library against `Telemetry` alone. Only the application at the top chooses an SDK.

## Using it

```lean
import Telemetry
import Telemetry.Sdk

open Telemetry

def solve : TelemetryT IO Unit :=
  spanning "solve" (attrs := [("solver.strategy", "greedy")]) do
    info "starting" [("attempt", 1)]
    span "score" fun s => do
      s.add [("score.total", 42)]

def main : IO Unit := do
  Sdk.installFromEnv
  try
    runTelemetry solve
  finally
    Sdk.shutdown
```

Run with nothing configured, that prints:

```
12:43:19.187 031b86fb     INFO  starting           attempt=1
12:43:19.188 031b86fb    0.0ms  score              score.total=42
12:43:19.187 031b86fb    0.8ms  solve              solver.strategy=greedy
```

The record and both spans share a trace id, and `score` appears before `solve` because a
parent finishes after its children.

Log records at `error` and above go to stderr; everything else goes to stdout.

With no SDK installed, `span` costs nothing: the action is handed an inert span that absorbs
every mutation, and no ids are generated and no clock is read.

Log records are never dropped that way. With no SDK they are rendered to stdout and stderr in
the readable format, so logging reads the wall clock on every call whether or not an SDK is
installed. No span context is installed either, so those lines carry a timestamp but no trace
id.

An exception escaping a span still reports the span, with status `error` and the exception's
message, and is re-raised unchanged.

## Testing instrumentation

`capture` runs an action with an in-memory exporter and returns its result alongside 
everything that reached the exporter:

```lean
import Telemetry.Testing

open Telemetry Telemetry.Testing

def solveIsInstrumented : IO Bool := do
  let (_, captured) ← capture (runTelemetry solve)
  return captured.spans.map (·.name) == #["score", "solve"]
    && captured.logs.map (·.body) == #["starting"]
```

## Configuration

Standard OpenTelemetry environment variables throughout.

| Variable | Meaning | Default |
|---|---|---|
| `OTEL_SDK_DISABLED` | When `true`, no SDK is installed at all. | `false` |
| `OTEL_SERVICE_NAME` | `service.name` on the resource. | unset |
| `OTEL_RESOURCE_ATTRIBUTES` | Comma-separated `key=value` pairs added to the resource. | unset |
| `OTEL_TRACES_EXPORTER` | Comma-separated list of `console`, `file`, `none`. | `console` |
| `OTEL_LOGS_EXPORTER` | As above, for log records. | `console` |
| `OTEL_EXPORTER_CONSOLE_FORMAT` | `pretty` or `otlp_json`. | `pretty` |
| `OTEL_EXPORTER_FILE_DIRECTORY` | Directory for segment files. | `telemetry` |
| `OTEL_EXPORTER_FILE_MAX_SIZE` | Segment size threshold in bytes. | `8388608` |
| `OTEL_EXPORTER_FILE_MAX_SEGMENTS` | Segments retained before the oldest is deleted. | `8` |

`OTEL_EXPORTER_CONSOLE_FORMAT=otlp_json` gives stdout over to the machine, at which point the
readable format is simply unavailable on that stream. Run the file exporter alongside the
console one to have both at once.

A value this library cannot act on produces a warning on stderr and is then ignored, rather
than being obeyed in some approximate way. `OTEL_TRACES_SAMPLER` is standard but not honoured
here, and is ignored in silence.

Resource attributes are assembled in increasing order of precedence: detected values
(`host.name`, `process.pid`), then `OTEL_RESOURCE_ATTRIBUTES`, then `OTEL_SERVICE_NAME`.

## File output

Segments are named `telemetry-NNNNNN.jsonl` and numbered monotonically. Nothing is ever
renamed or truncated: rotation is opening the next file, and a restart continues one above the
highest number already present. Once the segment count exceeds the limit, the lowest-numbered
segments are deleted.

If the directory cannot be created or written, installation fails rather than starting
quietly without it.

A collector picks the files up with the `otlpjsonfile` receiver:

```yaml
receivers:
  otlpjsonfile:
    include:
      - /var/log/telemetry/telemetry-*.jsonl

exporters:
  otlp:
    endpoint: collector.example.com:443

service:
  pipelines:
    traces:
      receivers: [otlpjsonfile]
      exporters: [otlp]
    logs:
      receivers: [otlpjsonfile]
      exporters: [otlp]
```

## Not implemented

Metrics, sampling, W3C `traceparent` propagation between processes, a direct OTLP/HTTP
exporter, batching, and span attribute limits.

## Building

```sh
lake build
lake test
```
