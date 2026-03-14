![Anmite Touch Mac logo](Resources/AppIconSource/logo.png)

# Anmite Touch Mac

Native macOS menu bar app project for using selected USB touch displays as pointer, drag, and scrolling input on macOS.

This repository is now Xcode-only. It is no longer built or packaged via SwiftPM scripts.

## Features

- Menu bar app that runs in the background on macOS
- Auto-connect on launch
- Automatic reconnect scan when the touch monitor is unplugged and plugged back in again
- Prefilled support for the detected Anmite touchscreen device:
  - Vendor ID `10176`
  - Product ID `2137`
- One-finger pointer movement on the touch display
- Tap-to-click recognition based on short press and release
- Drag recognition with movement thresholding
- Vertical one-finger scroll detection anywhere on the touch display
- Inverted scrolling tuned for natural webpage/document scrolling
- Momentum scrolling that continues briefly after release and decelerates smoothly
- Cursor handoff to the touched display before synthetic interaction begins
- First-launch permission prompting for Accessibility and Input Monitoring
- Settings window for device IDs, display selection, detected displays, and permission status

## Open In Xcode

Open the Xcode project directly:

```bash
/Users/christian/anmite-touch-mac/Anmite Touch Mac.xcodeproj
```

Or in Xcode:

1. `File > Open...`
2. Select [Anmite Touch Mac.xcodeproj](/Users/christian/anmite-touch-mac/Anmite%20Touch%20Mac.xcodeproj)

## Debug Build In Xcode

1. Select the `Anmite Touch Mac` scheme
2. Select destination `My Mac`
3. Use `Product > Run` or `Product > Build`

That uses Xcode’s `Debug` configuration.

## Release Build In Xcode

For a local release build:

1. `Product > Scheme > Edit Scheme...`
2. Set `Run` or `Archive` to `Release`
3. Use `Product > Build` or `Product > Archive`

For a production-style app bundle, use Xcode’s archive flow:

1. `Product > Archive`
2. Open Organizer
3. Sign/export from the archive

## Project Layout

- `Anmite Touch Mac.xcodeproj`: native macOS Xcode project
- `Sources/App`: menu bar app UI
- `Sources/Core`: HID capture, gesture recognition, display mapping, and event injection
- `Resources/Info.plist`: app bundle metadata
- `Resources/Assets.xcassets`: app icon asset catalog
- `Resources/AppIconSource/logo.png`: original logo source image

## Permissions

The app needs:

- `System Settings > Privacy & Security > Input Monitoring`
- `System Settings > Privacy & Security > Accessibility`

If you rebuild/sign the app in a way that changes its identity, macOS may require you to grant those permissions again.

## Bundle Identifier

The app is configured with the public bundle identifier:

```text
com.christianhuelsemeyer.anmitetouchmac
```
