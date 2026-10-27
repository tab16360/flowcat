#!/bin/bash
# Renders panel previews with sample data in English and Chinese, then composes
# the hero, comparison and demo images used by the README and the site.
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/build.sh
binary="build/流量喵.app/Contents/MacOS/FlowCat"
out="docs/assets/screens"
mkdir -p "$out"
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/trafficledger-clang-cache"
compose=$(mktemp "${TMPDIR:-/tmp}/flowcat-compose.XXXXXX")
trap 'rm -f "$compose" "$out"/preview-*.json' EXIT
xcrun swiftc -swift-version 5 -module-cache-path "$CLANG_MODULE_CACHE_PATH" scripts/Compose.swift -o "$compose"
for lang in en zh; do
    "$binary" --lang-$lang --render-preview "$out/network-$lang.png" --current-network "Studio 5G"
    "$binary" --lang-$lang --render-preview "$out/disk-$lang.png" --disk
    "$binary" --lang-$lang --render-preview "$out/disk-dark-$lang.png" --disk --dark
    "$binary" --lang-$lang --render-preview "$out/disk-7d-$lang.png" --disk --seven
    "$binary" --lang-$lang --render-preview "$out/health-$lang.png" --disk --health
    "$binary" --lang-$lang --render-preview "$out/alerts-$lang.png" --alerts --alert-detail
    "$binary" --lang-$lang --render-preview "$out/settings-$lang.png" --settings
    "$binary" --lang-$lang --render-menu-preview "$out/status-item-$lang.png" --status-item
    "$binary" --lang-$lang --render-menu-preview "$out/menu-bar-modes-$lang.png"
    "$compose" "$out" "$lang"
    # The composites are large; the site loads JPEG copies to keep the hero fast.
    for name in hero compare; do
        sips -s format jpeg -s formatOptions 82 "$out/$name-$lang.png" --out "$out/$name-$lang.jpg" >/dev/null
        rm "$out/$name-$lang.png"
    done
done
echo "Screenshots: $out"
