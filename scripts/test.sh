#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/trafficledger-clang-cache"
test_binary=$(mktemp "${TMPDIR:-/tmp}/trafficledger-tests.XXXXXX")
integration_binary=$(mktemp "${TMPDIR:-/tmp}/flowcat-update-tests.XXXXXX")
trap 'rm -f "$test_binary" "$integration_binary"' EXIT
xcrun swiftc -swift-version 5 -module-cache-path "$CLANG_MODULE_CACHE_PATH" Sources/Core.swift Sources/UpdateInfo.swift Sources/UpdateInstaller.swift Tests/main.swift -o "$test_binary"
"$test_binary"

xcrun swiftc -swift-version 5 -module-cache-path "$CLANG_MODULE_CACHE_PATH" Sources/UpdateInfo.swift Sources/UpdateInstaller.swift Tests/UpdateIntegration.swift -o "$integration_binary"
"$integration_binary"
