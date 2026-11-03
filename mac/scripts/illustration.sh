#!/bin/zsh
# Renders the vector headphone illustration to a PNG:  scripts/illustration.sh [out.png]
set -euo pipefail
cd "$(dirname "$0")/.."
SDK=$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX2[0-6].*.sdk | sort -V | tail -1)
mkdir -p build
swiftc -parse-as-library -swift-version 5 -sdk "$SDK" -target "$(uname -m)-apple-macos14.0" \
    Sources/SonyControl/UI/Window/HeadphoneIllustration.swift scripts/illustration.swift -o build/illustration-tool
build/illustration-tool "${1:-build/illustration.png}"
