#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/trafficledger-clang-cache"
smoke_binary=$(mktemp "${TMPDIR:-/tmp}/flowcat-helper-smoke.XXXXXX")
trap 'rm -f "$smoke_binary"' EXIT
xcrun swiftc -swift-version 5 -module-cache-path "$CLANG_MODULE_CACHE_PATH" Sources/Core.swift Sources/UpdateInfo.swift Sources/UpdateInstaller.swift scripts/UpdateHelperSmoke.swift -o "$smoke_binary"
"$smoke_binary" "$PWD/build/流量喵.app"
