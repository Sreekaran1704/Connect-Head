#!/bin/sh
# Builds Connect Head, waits for a phone with USB debugging, installs and opens it.
set -e
cd "$(dirname "$0")"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
export JAVA_HOME="${JAVA_HOME:-$(/usr/libexec/java_home -v 21)}"
ADB="$ANDROID_HOME/platform-tools/adb"

./gradlew -q :app:assembleDebug
echo "Waiting for the phone (plug in USB, allow USB debugging)..."
"$ADB" wait-for-device
echo "Phone connected: $("$ADB" shell getprop ro.product.model | tr -d '\r')"
"$ADB" install -r -t app/build/outputs/apk/debug/app-debug.apk >/dev/null
"$ADB" shell am start -n local.connecthead/.MainActivity >/dev/null
echo "Connect Head is open on the phone."
