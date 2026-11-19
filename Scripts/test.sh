#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/modules
xcrun swiftc -swift-version 5 -parse-as-library -module-name MeetConference \
  -module-cache-path "$PWD/build/modules" Sources/Shared/*.swift Sources/App/Vault.swift Sources/App/Loopback.swift Sources/Extension/*.swift Tests/Tests.swift -o build/tests
./build/tests
