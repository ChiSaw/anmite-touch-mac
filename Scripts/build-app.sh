#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${1:-release}"
APP_NAME="Anmite Touch Mac"
EXECUTABLE_NAME="TouchMonitorMenuBarApp"
OUTPUT_DIR="$ROOT_DIR/dist"
APP_DIR="$OUTPUT_DIR/$APP_NAME.app"
ICONSET_DIR="$OUTPUT_DIR/TouchMonitor.iconset"
ICON_FILE="$APP_DIR/Contents/Resources/TouchMonitor.icns"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
BUNDLE_IDENTIFIER="com.christianhuelsemeyer.anmitetouchmac"

mkdir -p "$OUTPUT_DIR"

swift build -c "$CONFIGURATION" --product "$EXECUTABLE_NAME"
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"

rm -rf "$APP_DIR" "$ICONSET_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$ROOT_DIR/AppResources/TouchMonitorMenuBarApp/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$BIN_DIR/$EXECUTABLE_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"
chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"

/usr/bin/swift "$ROOT_DIR/Scripts/generate_app_icon.swift" "$ICONSET_DIR"
iconutil -c icns "$ICONSET_DIR" -o "$ICON_FILE"
rm -rf "$ICONSET_DIR"

codesign --force --deep --sign "$SIGNING_IDENTITY" --identifier "$BUNDLE_IDENTIFIER" "$APP_DIR"

echo "Built app bundle at: $APP_DIR"
