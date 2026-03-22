#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="Dynatrace Agent"
BUNDLE_ID="com.dynatrace.macosagent"
BUILD_DIR="$PROJECT_DIR/build"
APP_PATH="$BUILD_DIR/${APP_NAME}.app"
PKG_PATH="$BUILD_DIR/DynatraceAgent.pkg"

# Build the .app first
echo "Building app bundle..."
"$SCRIPT_DIR/build-app.sh"

# Package it
echo "Creating installer package..."
PKG_ROOT="$BUILD_DIR/pkgroot"
rm -rf "$PKG_ROOT"
mkdir -p "$PKG_ROOT/Applications"
cp -R "$APP_PATH" "$PKG_ROOT/Applications/"

pkgbuild \
    --root "$PKG_ROOT" \
    --install-location / \
    --identifier "$BUNDLE_ID" \
    --version "1.0" \
    "$PKG_PATH"

rm -rf "$PKG_ROOT"

echo ""
echo "Installer ready: $PKG_PATH"
echo ""
echo "To install: open \"$PKG_PATH\""
