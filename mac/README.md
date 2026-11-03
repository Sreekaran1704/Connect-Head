# Connect Head (macOS)

A Mac app for the Sony ULT WEAR (WH-ULT900N), replacing Sony's app. It has a main window with a
sidebar (Overview, Sound, Equalizer, Devices, Settings) and an optional menu-bar icon for quick access:

- **Sound:** noise cancelling, ambient sound (level and focus on voice) or off, plus the NC/AMB button.
- **EQ:** presets, Clear Bass and 5 bands.
- **Devices:** the phones/computers paired with the headphones. Connect, disconnect, or move the
  audio to another connected device ("Play here").
- **Settings:** DSEE, LDAC preference, multipoint, voice guidance, voice assistant and more.
- **⌃⌥N** cycles Noise Cancelling → Ambient → Off from anywhere, with an on-screen badge.
- Battery in the menu bar, and a notification at 20% and 10%.
- Launch at login (Options menu, enabled on first launch of the installed copy).

## Build & run

```bash
./build.sh --install   # builds, copies to /Applications, and launches it
```

The first launch asks for Bluetooth access; allow it. The headphones must already be paired
in System Settings → Bluetooth. Because the app is ad-hoc signed, macOS asks again after every
rebuild. Signing with a stable certificate would stop that.

`scripts/preview.sh [dir] [dark]` renders every page to PNGs with sample data, no headphones needed.
(The translucent sidebar doesn't show up in these snapshots.)

`scripts/make-icon.swift` regenerates `Resources/AppIcon.icns`.

Probe the protocol against the running app with `scripts/send.swift <type> <payload…>`
(for example `scripts/send.swift 0c 56 00` re-reads the EQ).

Build notes for this machine (Command Line Tools only, no Xcode):
- SwiftPM's manifest library is broken in this CLT install, so `build.sh` calls `swiftc` directly.
- On the macOS 27 SDK, SwiftUI's `@State` is a macro whose plugin ships only with Xcode, so the
  script builds against the newest older SDK (26.x).

## How it works

The headphones expose a Sony RFCOMM service (UUID `956C7B26-…` for protocol v2). The app opens
that channel with IOBluetooth and speaks the framed protocol that the
[Gadgetbridge](https://codeberg.org/Freeyourgadget/Gadgetbridge) project reverse-engineered:

| File | Role |
| --- | --- |
| `Protocol/Frame.swift` | Framing, escaping, checksum, stream splitting |
| `Protocol/Commands.swift` | Command bytes and parsing of replies into `HeadphoneState` |
| `Bluetooth/HeadphoneController.swift` | RFCOMM link, init handshake, one-at-a-time ACK queue |
| `System/` | Global hotkey, on-screen badge, battery alerts, login item |
| `UI/Window/` | Main window: sidebar and pages |
| `UI/` | Menu-bar popover |

Multipoint device management uses the second command family (`0x0e`), as documented by
[mos9527/SonyHeadphonesClient](https://github.com/mos9527/sonyheadphonesclient)'s libmdr.
Unlike other Sony models, the ULT WEAR adds an extra `0x01` byte to EQ messages; the app detects it.

Settings appear only after the headphones report them, so unsupported ones stay hidden.

Debug the traffic with:

```bash
/usr/bin/log stream --predicate 'subsystem == "local.sonycontrol"' --level debug
```

The same `Protocol/` logic is meant to be ported to Kotlin for the Android app.
