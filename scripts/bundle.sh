#!/usr/bin/env bash
set -euo pipefail
# Display name (used for the .app bundle directory).
APP_NAME="Cloudup Snap"
# Executable name inside the bundle (must match CFBundleExecutable; no spaces).
EXECUTABLE_NAME="CloudupSnap"
# SwiftPM product/target name.
SWIFT_PRODUCT="CloudupSnap"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT/.build/release"
APP_DIR="$ROOT/build/$APP_NAME.app"
TEMPLATE="$ROOT/Sources/CloudupSnap/App/Info.plist.template"

cd "$ROOT"
swift build -c release --product "$SWIFT_PRODUCT"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BUILD_DIR/$SWIFT_PRODUCT" "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME"
cp "$TEMPLATE" "$APP_DIR/Contents/Info.plist"

# Build the AppIcon.icns from the Cloudup glyph. Skip if it's already present
# and newer than the generator script.
ICONSET="$ROOT/build/AppIcon.iconset"
ICNS="$ROOT/build/AppIcon.icns"
GEN_SCRIPT="$ROOT/tools/gen-icon.swift"
if [ ! -f "$ICNS" ] || [ "$GEN_SCRIPT" -nt "$ICNS" ]; then
  rm -rf "$ICONSET"
  swift "$GEN_SCRIPT" "$ICONSET" >/dev/null
  iconutil -c icns -o "$ICNS" "$ICONSET"
fi
cp "$ICNS" "$APP_DIR/Contents/Resources/AppIcon.icns"

# Copy any SwiftPM-generated resource bundle the executable carries
if [ -d "$BUILD_DIR/CloudupSnap_CloudupSnap.bundle" ]; then
  cp -R "$BUILD_DIR/CloudupSnap_CloudupSnap.bundle" "$APP_DIR/Contents/Resources/"
fi

# Ad-hoc codesign the bundle so the TCC database can track permissions by a
# stable identifier (com.bongnam.cloudupsnap from Info.plist). Without this,
# every rebuild looks like a different app to TCC and Screen Recording grants
# don't stick.
codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1
echo "Built and ad-hoc signed: $APP_DIR"
