#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/trafficledger-clang-cache"
test_binary=$(mktemp "${TMPDIR:-/tmp}/trafficledger-tests.XXXXXX")
integration_binary=$(mktemp "${TMPDIR:-/tmp}/flowcat-update-tests.XXXXXX")
disk_binary=$(mktemp "${TMPDIR:-/tmp}/flowcat-disk-tests.XXXXXX")
native_object=$(mktemp "${TMPDIR:-/tmp}/flowcat-hardware.XXXXXX")
trap 'rm -f "$test_binary" "$integration_binary" "$disk_binary" "$native_object"' EXIT
xcrun swiftc -swift-version 5 -module-cache-path "$CLANG_MODULE_CACHE_PATH" Sources/Core.swift Sources/DiskCore.swift Sources/UpdateInfo.swift Sources/UpdateInstaller.swift Tests/main.swift -o "$test_binary"
"$test_binary"

xcrun swiftc -swift-version 5 -module-cache-path "$CLANG_MODULE_CACHE_PATH" Sources/UpdateInfo.swift Sources/UpdateInstaller.swift Tests/UpdateIntegration.swift -o "$integration_binary"
"$integration_binary"

xcrun clang -O2 -c Sources/HardwareBridge.c -o "$native_object"
xcrun swiftc -swift-version 5 -module-cache-path "$CLANG_MODULE_CACHE_PATH" -import-objc-header Sources/HardwareBridge.h Sources/Core.swift Sources/DiskCore.swift Sources/DiskMonitor.swift Tests/DiskIntegration.swift "$native_object" -framework AppKit -framework IOKit -o "$disk_binary"
"$disk_binary"
