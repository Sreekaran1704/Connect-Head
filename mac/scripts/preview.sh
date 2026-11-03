#!/bin/zsh
# Renders every page of the main window to PNGs with sample data, no Bluetooth needed.
#   scripts/preview.sh [output dir] [dark]
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${1:-build/preview}"
SDK=$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX2[0-6].*.sdk | sort -V | tail -1)
mkdir -p build

swiftc -parse-as-library -swift-version 5 -D PREVIEW -sdk "$SDK" \
    -target "$(uname -m)-apple-macos14.0" -framework IOBluetooth \
    $(find Sources/SonyControl -name '*.swift' ! -name App.swift) scripts/preview.swift \
    -o build/preview-renderer

build/preview-renderer "$OUT" "${2:-light}"
