#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
staging=$(mktemp -d "${TMPDIR:-/tmp}/flowcat-icons.XXXXXX")
trap 'rm -rf "$staging"' EXIT
xcrun swiftc -swift-version 5 Sources/BrandIcon.swift scripts/IconBuilder.swift -o "$staging/icon-builder"
"$staging/icon-builder" "$staging/FlowCat.iconset"
mkdir -p assets docs/assets
iconutil -c icns "$staging/FlowCat.iconset" -o assets/FlowCat.icns
cp "$staging/FlowCat.iconset/icon_512x512.png" docs/assets/app-icon.png
echo "Generated application icon and website preview."
