# Anmite Touch Mac

Native macOS menu bar app project for using selected USB touch displays as pointer, drag, and scrolling input on macOS.

This repository is now Xcode-only. It is no longer built or packaged via SwiftPM scripts.

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
- `Sources/TouchMonitorMenuBarApp`: menu bar app UI
- `Sources/TouchMonitorPOC`: HID capture, gesture recognition, display mapping, and event injection
- `Resources/Info.plist`: app bundle metadata
- `Resources/Assets.xcassets`: app icon asset catalog
- `Resources/AppIconSource/logo.png`: original logo source image

## App Icon

The original logo source file is:

[logo.png](/Users/christian/anmite-touch-mac/Resources/AppIconSource/logo.png)

The actual app icon used by Xcode is in:

[AppIcon.appiconset](/Users/christian/anmite-touch-mac/Resources/Assets.xcassets/AppIcon.appiconset)

If you replace the logo, regenerate the icon sizes in the asset catalog or replace the PNGs in `AppIcon.appiconset`.

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
