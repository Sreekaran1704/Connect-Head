#!/bin/zsh
# Builds "Connect Head.app" with plain swiftc, so Command Line Tools are enough (no Xcode/SwiftPM).
#   ./build.sh            build into "build/Connect Head.app"
#   ./build.sh --install  also copy it to /Applications and relaunch it from there
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Connect Head.app"
INSTALLED="/Applications/Connect Head.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Pick the newest installed SDK older than macOS 27: from 27 on, SwiftUI's @State is a macro
# whose compiler plugin only ships with full Xcode.
SDK_DIR=/Library/Developer/CommandLineTools/SDKs
SDK=$(ls -d $SDK_DIR/MacOSX2[0-6].*.sdk $SDK_DIR/MacOSX1[4-9].*.sdk 2>/dev/null | sort -V | tail -1)
[[ -n "$SDK" ]] || SDK=$(xcrun --show-sdk-path)

swiftc -O -parse-as-library -swift-version 5 \
    -sdk "$SDK" \
    -target "$(uname -m)-apple-macos14.0" \
    -framework IOBluetooth \
    Sources/SonyControl/**/*.swift \
    -o "$APP/Contents/MacOS/ConnectHead"

cp Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc sign. macOS ties the Bluetooth permission to this signature, so it re-asks after rebuilds.
codesign --force --sign - --entitlements SonyControl.entitlements "$APP"

echo "Built $PWD/$APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x ConnectHead || true
    pkill -x SonyControl || true          # the app's previous name
    rm -rf "/Applications/SonyControl.app" "$INSTALLED"
    ditto "$APP" "$INSTALLED"
    open "$INSTALLED"
    echo "Installed $INSTALLED"
fi
