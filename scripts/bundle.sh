#!/usr/bin/env bash
set -euo pipefail
APP_NAME="Screenshotter"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT/.build/release"
APP_DIR="$ROOT/build/$APP_NAME.app"
TEMPLATE="$ROOT/Sources/Screenshotter/App/Info.plist.template"

cd "$ROOT"
swift build -c release --product "$APP_NAME"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BUILD_DIR/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$TEMPLATE" "$APP_DIR/Contents/Info.plist"

# Copy any SwiftPM-generated resource bundle the executable carries
if [ -d "$BUILD_DIR/Screenshotter_Screenshotter.bundle" ]; then
  cp -R "$BUILD_DIR/Screenshotter_Screenshotter.bundle" "$APP_DIR/Contents/Resources/"
fi

echo "Built: $APP_DIR"
