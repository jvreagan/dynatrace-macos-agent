#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="Dynatrace Agent"
SWIFT_BUILD_DIR="$PROJECT_DIR/.build"
APP_DIR="/tmp/dynatrace-agent-build/${APP_NAME}.app"

echo "Building DynatraceAgent..."
cd "$PROJECT_DIR"
swift build -c release

echo "Creating app bundle..."
rm -rf "/tmp/dynatrace-agent-build"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$SWIFT_BUILD_DIR/release/DynatraceAgent" "$APP_DIR/Contents/MacOS/DynatraceAgent"
cp "$PROJECT_DIR/Sources/DynatraceAgent/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"

codesign --force --deep --sign - "$APP_DIR"

echo ""
echo "Build complete: $APP_DIR"
