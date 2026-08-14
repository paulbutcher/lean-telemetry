/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import TelemetryTest.Config
import TelemetryTest.File
import TelemetryTest.Id
import TelemetryTest.Install
import TelemetryTest.Layering
import TelemetryTest.Logging
import TelemetryTest.Monad
import TelemetryTest.Otlp
import TelemetryTest.Render
import TelemetryTest.Resource
import TelemetryTest.Trace
import TelemetryTest.Usage
import TelemetryTest.Value

def main : IO UInt32 :=
  TelemetryTest.runAll [
    ("config", TelemetryTest.Config.suite),
    ("file", TelemetryTest.File.suite),
    ("ids", TelemetryTest.Id.suite),
    ("install", TelemetryTest.Install.suite),
    ("layering", TelemetryTest.Layering.suite),
    ("logging", TelemetryTest.Logging.suite),
    ("monad", TelemetryTest.Monad.suite),
    ("otlp", TelemetryTest.Otlp.suite),
    ("render", TelemetryTest.Render.suite),
    ("resource", TelemetryTest.Resource.suite),
    ("trace", TelemetryTest.Trace.suite)
  ]
