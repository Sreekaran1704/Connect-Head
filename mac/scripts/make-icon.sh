#!/bin/zsh
# Renders the app icon (Mac .icns and the Android launcher foreground):  scripts/make-icon.sh
set -euo pipefail
cd "$(dirname "$0")/.."
SDK=$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX2[0-6].*.sdk | sort -V | tail -1)
mkdir -p build
swiftc -parse-as-library -swift-version 5 -sdk "$SDK" -target "$(uname -m)-apple-macos14.0" \
    Sources/SonyControl/UI/Window/HeadphoneIllustration.swift scripts/make-icon.swift -o build/make-icon
build/make-icon
iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
