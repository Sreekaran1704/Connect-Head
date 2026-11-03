# Connect Head for Android

The Android version of Connect Head, the Sony ULT WEAR (WH-ULT900N) companion app. Same
protocol and the same printed-edition look as the Mac app in `../mac`.

- **Overview**: battery tick dial, now playing (any app, via media sessions), sound mode,
  devices, and an EQ curve you drag.
- **Sound, Equalizer, Devices, Settings**: the headphone controls, with print-style faders
  and toggles.
- **Listening**: time by day and hour, top artists and tracks, which app, and media volume
  while playing through the headphones. Stored only on the phone, kept 120 days.

## Build and install

```sh
./install.sh            # builds, waits for a USB-debugging phone, installs, opens
./gradlew :app:testDebugUnitTest   # protocol tests
```

Needs the Android SDK (`local.properties`) and JDK 21.

## Permissions

- **Nearby devices** (Bluetooth connect): to talk to the headphones.
- **Notification access**: lets the app read other apps' media sessions for Now Playing and
  the listening history. It doesn't read or keep notifications.
