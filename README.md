# Anmite Touch Mac

macOS menu bar app and Swift package for using selected USB touch displays as pointer and scroll input on macOS.

The project currently targets touchscreens that expose a usable absolute-pointer HID path on macOS. It adds:

- tap recognition
- drag recognition
- vertical scroll recognition
- momentum scrolling
- menu bar control and settings UI

It does not create native Apple multi-touch gestures system-wide, and it does not install a kernel or DriverKit virtual touch device.

## Project Layout

- `Sources/TouchMonitorPOC`: shared HID capture, gesture recognition, display mapping, and event injection
- `Sources/TouchMonitorCLI`: command-line tool for debugging and reverse engineering
- `Sources/TouchMonitorMenuBarApp`: menu bar app UI
- `AppResources/TouchMonitorMenuBarApp`: app bundle metadata
- `Scripts/build-app.sh`: builds and packages a real `.app` bundle

## Build

Build the package from Terminal:

```bash
cd /Users/christian/anmite-touch-mac
swift build
```

Build the menu bar app bundle:

```bash
cd /Users/christian/anmite-touch-mac
./Scripts/build-app.sh debug
```

The packaged app will be written to:

```bash
/Users/christian/anmite-touch-mac/dist/Anmite Touch Mac.app
```

## Open In Xcode

This project is a Swift package and is ready to open directly in Xcode.

1. Open Xcode.
2. Choose `File > Open...`
3. Select `/Users/christian/anmite-touch-mac`

Xcode will load the package and expose these main schemes:

- `TouchMonitorMenuBarApp`
- `touch-monitor-cli`

Use the `TouchMonitorMenuBarApp` scheme to run the menu bar app from Xcode.

## Permissions

The app needs these macOS permissions:

- `System Settings > Privacy & Security > Input Monitoring`
- `System Settings > Privacy & Security > Accessibility`

After rebuilding the app bundle, re-grant permissions if macOS treats the bundle as changed.

## Signing

The app bundle is prepared with the public bundle identifier:

```text
com.christianhuelsemeyer.anmitetouchmac
```

`Scripts/build-app.sh` signs the bundle with an ad-hoc signature by default so local builds can run immediately.

For a real public release, provide a signing identity when building:

```bash
SIGNING_IDENTITY="Developer ID Application: Your Name" ./Scripts/build-app.sh release
```

## Debug CLI

List HID devices:

```bash
./.build/debug/touch-monitor-cli --list
```

Run the injector against a known device and display:

```bash
./.build/debug/touch-monitor-cli --vendor-id 10176 --product-id 2137 --display-id 3 --inject
```
