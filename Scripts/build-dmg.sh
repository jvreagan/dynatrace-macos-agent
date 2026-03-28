#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="Dynatrace Agent"
APP_DIR="/tmp/dynatrace-agent-build/${APP_NAME}.app"
STAGING="/tmp/dynatrace-agent-dmg"
DMG_PATH="$PROJECT_DIR/build/DynatraceAgent.dmg"

# Build the .app
"$SCRIPT_DIR/build-app.sh"

# Stage DMG contents
echo "Staging DMG..."
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP_DIR" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

# Create DMG
echo "Creating DMG..."
mkdir -p "$(dirname "$DMG_PATH")"
rm -f "$DMG_PATH"
hdiutil create \
    -volname "Dynatrace Agent" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

rm -rf "$STAGING" "/tmp/dynatrace-agent-build"

echo ""
echo "DMG ready: $DMG_PATH"
