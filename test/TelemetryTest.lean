/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
module

import TelemetryTest.Config
import TelemetryTest.Consumer
import TelemetryTest.File
import TelemetryTest.Http
import TelemetryTest.Id
import TelemetryTest.Install
import TelemetryTest.Json
import TelemetryTest.Layering
import TelemetryTest.Logging
import TelemetryTest.Monad
import TelemetryTest.Otlp
import TelemetryTest.Render
import TelemetryTest.Resource
import TelemetryTest.Testing
import TelemetryTest.Trace
import TelemetryTest.Usage
import TelemetryTest.Value

public def main : IO UInt32 :=
  TelemetryTest.runAll [
    ("config", TelemetryTest.Config.suite),
    ("consumer", TelemetryTest.Consumer.suite),
    ("file", TelemetryTest.File.suite),
    ("http", TelemetryTest.Http.suite),
    ("ids", TelemetryTest.Id.suite),
    ("install", TelemetryTest.Install.suite),
    ("json", TelemetryTest.Json.suite),
    ("layering", TelemetryTest.Layering.suite),
    ("logging", TelemetryTest.Logging.suite),
    ("monad", TelemetryTest.Monad.suite),
    ("otlp", TelemetryTest.Otlp.suite),
    ("render", TelemetryTest.Render.suite),
    ("resource", TelemetryTest.Resource.suite),
    ("testing", TelemetryTest.Testing.suite),
    ("trace", TelemetryTest.Trace.suite),
    ("usage", TelemetryTest.Usage.suite)
  ]
