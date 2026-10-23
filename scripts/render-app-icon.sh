#!/usr/bin/env bash
# Export the approved vector mark to the 1024px master and every macOS icon size.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="${ROOT_DIR}/docs/design/committed-app-icon.svg"
ICONSET="${ROOT_DIR}/CommitStandings/Assets.xcassets/AppIcon.appiconset"

if ! command -v rsvg-convert >/dev/null 2>&1; then
    echo "Install librsvg (brew install librsvg) to render the app icon." >&2
    exit 1
fi

rsvg-convert --width 1024 --height 1024 "${SOURCE}" \
    --output "${ROOT_DIR}/docs/design/committed-app-icon.png"
for size in 16 32 128 256 512; do
    for scale in 1 2; do
        suffix=""
        if [[ "${scale}" == 2 ]]; then suffix="@2x"; fi
        pixels=$((size * scale))
        rsvg-convert --width "${pixels}" --height "${pixels}" "${SOURCE}" \
            --output "${ICONSET}/icon_${size}x${size}${suffix}.png"
    done
done
