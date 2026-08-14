/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Telemetry.Sdk.Config
import TelemetryTest.Harness

namespace TelemetryTest.Config

open Telemetry.Sdk

private def env (values : List (String × String)) : String → Option String :=
  fun name => values.lookup name

private def parsed (values : List (String × String)) : Config :=
  (Config.parse (env values)).1

private def warnings (values : List (String × String)) : List String :=
  (Config.parse (env values)).2

def suite : TestM Unit := do
  let defaults := parsed []
  checkEq "with nothing set both signals go to the console"
    (defaults.traces, defaults.logs) ([ExporterKind.console], [ExporterKind.console])
  checkEq "and in the readable format" defaults.consoleFormat ConsoleFormat.pretty
  check "and the SDK is enabled" (!defaults.disabled)

  check "OTEL_SDK_DISABLED is honoured"
    (parsed [("OTEL_SDK_DISABLED", "TRUE")]).disabled
  check "anything else leaves it enabled"
    (!(parsed [("OTEL_SDK_DISABLED", "yes")]).disabled)

  checkEq "the exporter list is split and trimmed"
    (parsed [("OTEL_TRACES_EXPORTER", "console, file")]).traces [.console, .file]
  checkEq "'none' selects nothing" (parsed [("OTEL_LOGS_EXPORTER", "none")]).logs []
  checkEq "the two signals are configured apart"
    (parsed [("OTEL_TRACES_EXPORTER", "file"), ("OTEL_LOGS_EXPORTER", "console")]).traces [.file]

  checkEq "an unsupported exporter is reported, not obeyed"
    (parsed [("OTEL_TRACES_EXPORTER", "otlp,console")]).traces [.console]
  checkEq "and it produces exactly one warning"
    (warnings [("OTEL_TRACES_EXPORTER", "otlp,console")]).length 1

  checkEq "the console format can be switched to OTLP"
    (parsed [("OTEL_EXPORTER_CONSOLE_FORMAT", "otlp_json")]).consoleFormat ConsoleFormat.otlpJson
  checkEq "an unknown format warns and keeps the default"
    ((parsed [("OTEL_EXPORTER_CONSOLE_FORMAT", "yaml")]).consoleFormat,
      (warnings [("OTEL_EXPORTER_CONSOLE_FORMAT", "yaml")]).length)
    (ConsoleFormat.pretty, 1)

  let file := (parsed [("OTEL_EXPORTER_FILE_DIRECTORY", "/var/log/telemetry"),
    ("OTEL_EXPORTER_FILE_MAX_SIZE", "1024"), ("OTEL_EXPORTER_FILE_MAX_SEGMENTS", "3")]).file
  checkEq "the file limits are read" (file.maxBytes, file.maxSegments) (1024, 3)
  checkEq "as is the directory" file.directory.toString "/var/log/telemetry"
  checkEq "a size that is not a number warns and keeps the default"
    ((parsed [("OTEL_EXPORTER_FILE_MAX_SIZE", "10MB")]).file.maxBytes,
      (warnings [("OTEL_EXPORTER_FILE_MAX_SIZE", "10MB")]).length)
    (File.defaultMaxBytes, 1)

  checkEq "a sampler this library cannot honour is ignored in silence"
    (warnings [("OTEL_TRACES_SAMPLER", "traceidratio")]).length 0

end TelemetryTest.Config
