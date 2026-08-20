/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
module

/-!
Attribute names from the OpenTelemetry semantic conventions, so that instrumentation written
in other packages agrees on spelling. These are the current stable forms, not the older
`http.method` and `http.status_code`.
-/

public section

namespace Telemetry.Conventions

def serviceName : String := "service.name"
def serviceVersion : String := "service.version"
def hostName : String := "host.name"
def processPid : String := "process.pid"
def httpRequestMethod : String := "http.request.method"
def httpRoute : String := "http.route"
def httpResponseStatusCode : String := "http.response.status_code"
def urlPath : String := "url.path"
def urlQuery : String := "url.query"
def dbSystemName : String := "db.system.name"
def dbOperationName : String := "db.operation.name"
def errorType : String := "error.type"

end Telemetry.Conventions
