# lean-telemetry

OpenTelemetry tracing and logging for Lean 4 applications.

It produces spans and log records and writes them in a readable form for a developer watching a
terminal, as OTLP/JSON for an OpenTelemetry Collector to forward to a backend, or as one flat
JSON object per row for a store that queries rows rather than trees.

Reaching a backend is the collector's job, and there is no vendor-specific code anywhere in this
library. Telemetry leaves the process on stdout, on stderr, in files on disk, or over a loopback
socket to a collector in the same execution environment; what the collector does with it from
there is configured in the collector, not here.

## Libraries

| Library | Contents | Depends on |
|---|---|---|
| `Telemetry` | The API: `MonadTelemetry`, `span`, `spanning`, the log functions, semantic convention constants. | Lean core and Std only |
| `Telemetry.Sdk` | Resource detection, exporters, installation, configuration from the environment. | `Telemetry`, [`leancurl`](https://github.com/paulbutcher/leancurl) |
| `Telemetry.Parse` | Reading the flat format back into spans and log records. | `Telemetry.Sdk` |
| `Telemetry.Testing` | Test helpers. | `Telemetry.Sdk` |

`leancurl` binds to `libcurl`, so building this package needs `libcurl` and `pkg-config`
available. Instrumenting a library against `Telemetry` alone brings in no network code, but the
dependency is resolved package-wide, so a consumer's build needs `libcurl` present whether or not
it installs an SDK.

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
| `OTEL_TRACES_EXPORTER` | Comma-separated list of `console`, `file`, `otlp`, `none`. | `console` |
| `OTEL_LOGS_EXPORTER` | As above, for log records. | `console` |
| `OTEL_EXPORTER_CONSOLE_FORMAT` | `pretty`, `otlp_json` or `flat_json`. | `pretty` |
| `OTEL_EXPORTER_FILE_DIRECTORY` | Directory for segment files. | `telemetry` |
| `OTEL_EXPORTER_FILE_MAX_SIZE` | Segment size threshold in bytes. | `8388608` |
| `OTEL_EXPORTER_FILE_MAX_SEGMENTS` | Segments retained before the oldest is deleted. | `8` |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | Base URL; the signal's path is appended to it. | `http://localhost:4318` |
| `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` | Complete URL for spans, used as given. | base plus `/v1/traces` |
| `OTEL_EXPORTER_OTLP_LOGS_ENDPOINT` | Complete URL for log records, used as given. | base plus `/v1/logs` |
| `OTEL_EXPORTER_OTLP_PROTOCOL` | `http/json`. | `http/json` |
| `OTEL_EXPORTER_OTLP_TIMEOUT` | Per-export timeout in milliseconds. | `10000` |

Either machine format gives stdout over to the machine, at which point the readable format is
simply unavailable on that stream. Run the file exporter alongside the console one to have both
at once.

A value this library cannot act on produces a warning on stderr and is then ignored, rather
than being obeyed in some approximate way. `OTEL_TRACES_SAMPLER` is standard but not honoured
here, and is ignored in silence.

Resource attributes are assembled in increasing order of precedence: detected values
(`host.name`, `process.pid`), then `installFromEnv`'s `extraAttrs`, then
`OTEL_RESOURCE_ATTRIBUTES`, then `OTEL_SERVICE_NAME`.

`extraAttrs` is for what an application knows and the environment cannot be told, such as an
identifier for the execution environment it happens to be running in:

```lean
Sdk.installFromEnv (extraAttrs := [("faas.instance", .str instanceId)])
```

It sits below the environment, so a deployment can still override anything it sets.

## The flat format

`OTEL_EXPORTER_CONSOLE_FORMAT=flat_json` writes one self-contained JSON object per line, one per
span and one per log record, with the resource denormalised onto every row:

```json
{"time":"2025-08-14T11:54:31.882000000Z","duration_ms":8.123456,"name":"solve","trace.trace_id":"4bf92f3577b34da6a3ce929d0e0e4736","trace.span_id":"00f067aa0ba902b7","span.kind":"internal","status_code":0,"meta.signal_type":"trace","service.name":"timetabling","solver.strategy":"greedy"}
```

OTLP/JSON is unqueryable by a row-oriented store: an attribute lives at
`resourceSpans.0.scopeSpans.0.spans.3.attributes.7.value.stringValue`, at an index that varies
per span, and the resource sits once per envelope rather than on each row. CloudWatch Logs
Insights, Athena and Honeycomb's events API all want the opposite, and this is it. Flatness is
what the first two need; the field names are Honeycomb's rather than invented, so the third
ingests the same bytes with no mapping in between.

| Field | On | Meaning |
|---|---|---|
| `time` | both | RFC 3339 in UTC, with nine fractional digits. |
| `meta.signal_type` | both | `trace` for a span, `log` for a log record. |
| `trace.trace_id`, `trace.span_id` | both | Present on a log record only when it was emitted inside a span. |
| `trace.parent_id` | spans | Absent on a root span. |
| `duration_ms` | spans | Milliseconds, with six decimal places. |
| `name`, `span.kind` | spans | `span.kind` is `internal`, `server`, `client`, `producer` or `consumer`. |
| `status_code`, `status_message` | spans | The OTLP status numbers; the message is absent when there is none. |
| `severity`, `severity_code`, `body` | log records | The severity as text and as its OTLP number. |

Everything else on a row is an attribute, named exactly as the instrumentation named it.

### Reading it back

`Telemetry.Parse` turns a row back into the `SpanData` or `LogRecord` it was written from, for a
terminal tool that pretty-prints deployed output, or a forwarder that translates stdout to OTLP:

```lean
import Telemetry.Parse
import Telemetry.Sdk

open Telemetry

def reprint (line : String) : IO Unit :=
  match Parse.Flat.parse line with
  | .ok (.span data) => IO.println (Sdk.Console.renderSpan data)
  | .ok (.log record) => IO.println (Render.logRecord record)
  | .error message => IO.eprintln message
```

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

## OTLP over HTTP

Where a collector cannot read files, the `otlp` exporter POSTs the same OTLP/JSON to one over
HTTP. It exists for collectors in the same execution environment, and `http://localhost:4318` is
the target it is designed for; AWS Lambda, where the collector runs as an external extension and
its component set has no file receiver at all, is the case that motivated it.

```sh
OTEL_TRACES_EXPORTER=otlp OTEL_LOGS_EXPORTER=otlp
```

That scope is what keeps it small. There is no TLS, no authentication, no retry, no backoff and
no queueing, because the traffic is not expected to leave the machine and the collector owns
delivery once it has the data. Sending this across a network is not what it is for.

The payload is OTLP/JSON, which the collector's OTLP receiver accepts on its HTTP port. The
specification's default is `http/protobuf`, which this library has no encoder for, so
`OTEL_EXPORTER_OTLP_PROTOCOL` is warned about and ignored unless it is `http/json`.

`OTEL_EXPORTER_OTLP_ENDPOINT` is a base URL that the signal's path is appended to;
`OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` and `OTEL_EXPORTER_OTLP_LOGS_ENDPOINT` are complete URLs
used exactly as given.

Each export is its own connection. An execution environment that freezes between invocations
freezes both ends of a kept one, which would then be resumed against a peer that may long since
have dropped it.

### When the collector is not there

A failed export never reaches the application. A request does not fail, and a span's `report`
does not throw, because telemetry could not be delivered; the data is dropped and the failure is
reported on stderr instead.

A collector that is missing would otherwise produce one stderr line per span, so an outage is
reported when it starts and counted after that:

```
lean-telemetry: http://localhost:4318/v1/traces: Connection refused; further export failures
will be counted rather than reported
lean-telemetry: collector reachable again; 148 export(s) were dropped
```

A collector that answers but rejects the payload is treated the same way, with its status code in
place of the transport error. Nothing is opened at installation, so a collector that has not
started yet does not stop an application starting.

## Not implemented

Metrics, sampling, W3C `traceparent` propagation between processes, batching, span attribute
limits, and OTLP over gRPC or protobuf.

## Building

```sh
lake build
lake test
```

`libcurl` and `pkg-config` must be available; they are discovered at build time.
