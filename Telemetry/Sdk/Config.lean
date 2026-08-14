/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Telemetry.Sdk.File

/-!
Configuration comes from the standard OpenTelemetry environment variables. `OTEL_TRACES_SAMPLER`
is standard but not honoured here, and is ignored rather than rejected. Anything else that
cannot be acted on produces a warning, because telemetry that quietly fails to appear is the
worst failure this library has.
-/

namespace Telemetry.Sdk

inductive ExporterKind where
  | console | file
  deriving Repr, BEq, DecidableEq, Inhabited

inductive ConsoleFormat where
  | pretty | otlpJson
  deriving Repr, BEq, Inhabited

structure Config where
  disabled : Bool := false
  traces : List ExporterKind := [.console]
  logs : List ExporterKind := [.console]
  consoleFormat : ConsoleFormat := .pretty
  file : File.Config := {
    directory := "telemetry"
    maxBytes := File.defaultMaxBytes
    maxSegments := File.defaultMaxSegments
  }
  deriving Repr

namespace Config

private def normalise (s : String) : String := s.trimAscii.toString.toLower

private def parseExporters (spec : String) : List ExporterKind × List String :=
  spec.splitOn "," |>.foldl (init := ([], [])) fun (kinds, unknown) raw =>
    match normalise raw with
    | "" | "none" => (kinds, unknown)
    | "console" => (kinds ++ [.console], unknown)
    | "file" => (kinds ++ [.file], unknown)
    | other => (kinds, unknown ++ [other])

private def ignoring (setting value : String) : String :=
  s!"{setting}: ignoring unrecognised value '{value}'"

/-- Reads the whole configuration from `env`, alongside anything it could not act on. -/
def parse (env : String → Option String) : Config × List String := Id.run do
  let mut config : Config := {}
  let mut warnings : List String := []

  if let some value := env "OTEL_SDK_DISABLED" then
    config := { config with disabled := normalise value == "true" }

  for (setting, isTraces) in [("OTEL_TRACES_EXPORTER", true), ("OTEL_LOGS_EXPORTER", false)] do
    if let some value := env setting then
      let (kinds, unknown) := parseExporters value
      config := if isTraces then { config with traces := kinds } else { config with logs := kinds }
      warnings := warnings ++ unknown.map (ignoring setting)

  if let some value := env "OTEL_EXPORTER_CONSOLE_FORMAT" then
    match normalise value with
    | "pretty" => config := { config with consoleFormat := .pretty }
    | "otlp_json" => config := { config with consoleFormat := .otlpJson }
    | other => warnings := warnings ++ [ignoring "OTEL_EXPORTER_CONSOLE_FORMAT" other]

  if let some value := env "OTEL_EXPORTER_FILE_DIRECTORY" then
    config := { config with file := { config.file with directory := value } }

  if let some value := env "OTEL_EXPORTER_FILE_MAX_SIZE" then
    match value.trimAscii.toString.toNat? with
    | some size => config := { config with file := { config.file with maxBytes := size } }
    | none => warnings := warnings ++ [ignoring "OTEL_EXPORTER_FILE_MAX_SIZE" value]

  if let some value := env "OTEL_EXPORTER_FILE_MAX_SEGMENTS" then
    match value.trimAscii.toString.toNat? with
    | some count => config := { config with file := { config.file with maxSegments := count } }
    | none => warnings := warnings ++ [ignoring "OTEL_EXPORTER_FILE_MAX_SEGMENTS" value]

  return (config, warnings)

def fromEnv : IO (Config × List String) := do
  let mut values : List (String × String) := []
  for setting in ["OTEL_SDK_DISABLED", "OTEL_SERVICE_NAME", "OTEL_TRACES_EXPORTER",
      "OTEL_LOGS_EXPORTER", "OTEL_EXPORTER_CONSOLE_FORMAT", "OTEL_EXPORTER_FILE_DIRECTORY",
      "OTEL_EXPORTER_FILE_MAX_SIZE", "OTEL_EXPORTER_FILE_MAX_SEGMENTS"] do
    if let some value ← IO.getEnv setting then
      values := values ++ [(setting, value)]
  return parse fun setting => values.lookup setting

end Config

end Telemetry.Sdk
