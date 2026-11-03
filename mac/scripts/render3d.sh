#!/bin/zsh
# Renders the 3D headphone model from several angles:
#   scripts/render3d.sh [output dir] [Black|Off White|Forest Gray] [model file]
set -euo pipefail
cd "$(dirname "$0")/.."
SDK=$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX2[0-6].*.sdk | sort -V | tail -1)
mkdir -p build
swiftc -parse-as-library -swift-version 5 -sdk "$SDK" -target "$(uname -m)-apple-macos14.0" \
    Sources/SonyControl/UI/Model3D/HeadphoneScene.swift Sources/SonyControl/UI/Model3D/ModelStore.swift scripts/render3d.swift -o build/render3d-tool
build/render3d-tool "${1:-build/render3d}" "${2:-Forest Gray}" "${@:3}"
