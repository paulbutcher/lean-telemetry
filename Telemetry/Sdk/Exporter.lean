/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Telemetry.Sdk.Data

namespace Telemetry.Sdk

/--
Arrays rather than single values, even though nothing batches yet and each call carries exactly
one element, so that batching can arrive without breaking exporters.
-/
structure Exporter where
  exportSpans : Array SpanData → IO Unit
  exportLogs : Array LogRecord → IO Unit
  shutdown : IO Unit := pure ()

end Telemetry.Sdk
