#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
arch="${ARCH:-arm64}"
case "$arch" in arm64|x86_64) ;; *) echo "ARCH must be arm64 or x86_64" >&2; exit 1;; esac
app="build/流量喵.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/trafficledger-clang-cache"
xcrun clang -O2 -target "$arch-apple-macosx13.0" -c Sources/HardwareBridge.c -o build/HardwareBridge.o
xcrun swiftc -import-objc-header Sources/HardwareBridge.h build/HardwareBridge.o -swift-version 5 -O -target "$arch-apple-macosx13.0" -module-cache-path "$CLANG_MODULE_CACHE_PATH" Sources/*.swift -o "$app/Contents/MacOS/FlowCat" -framework AppKit -framework SwiftUI -framework ServiceManagement -framework CoreWLAN -framework CoreLocation -framework IOKit
cp Info.plist "$app/Contents/Info.plist"
cp assets/FlowCat.icns "$app/Contents/Resources/FlowCat.icns"
# Localized bundle name and permission prompts; English is the development region.
cp -R Resources/en.lproj Resources/zh-Hans.lproj "$app/Contents/Resources/"
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
echo "Built: $app ($arch)"
