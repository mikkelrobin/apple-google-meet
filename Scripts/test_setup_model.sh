#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/modules
# Compile the actual production model with an isolated in-memory credential store.
# The containing SwiftUI app's @main cannot share the test executable's entry point.
python3 - <<'PY'
from pathlib import Path
source = Path('Sources/App/CalendarMeetApp.swift').read_text()
model = source[source.index('@MainActor\nfinal class SetupModel'):source.index('struct SetupView:')]
Path('build/SetupModelUnderTest.swift').write_text('import SwiftUI\nimport UniformTypeIdentifiers\nimport ServiceManagement\n' + model)
PY
xcrun swiftc -swift-version 5 -parse-as-library -module-cache-path "$PWD/build/modules" \
  Sources/Shared/*.swift Sources/App/Loopback.swift build/SetupModelUnderTest.swift Tests/SetupModelTests.swift -o build/setup-model-tests
./build/setup-model-tests
