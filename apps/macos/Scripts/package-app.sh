#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
APP_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
: "${MICWISP_CLI_PATH:?Set MICWISP_CLI_PATH to the patched micyou-cli executable}"
if [ ! -x "$MICWISP_CLI_PATH" ]; then
  echo "micyou-cli is not an executable file: $MICWISP_CLI_PATH" >&2
  exit 1
fi

cd "$APP_ROOT"
swift build -c release
BIN_DIR=$(swift build -c release --show-bin-path)
RESOURCE_BUNDLE="$BIN_DIR/DesktopClient_DesktopClient.bundle"
if [ ! -d "$RESOURCE_BUNDLE" ]; then
  echo "SwiftPM resource bundle not found: $RESOURCE_BUNDLE" >&2
  exit 1
fi

APP_NAME=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$APP_ROOT/Info.plist")
APP="$APP_ROOT/dist/$APP_NAME.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
cp "$APP_ROOT/Info.plist" "$APP/Contents/Info.plist"
cp "$BIN_DIR/desktop-client" "$APP/Contents/MacOS/desktop-client"
cp "$MICWISP_CLI_PATH" "$APP/Contents/Helpers/micyou-cli"
cp -R "$RESOURCE_BUNDLE" "$APP/Contents/Resources/"
echo "Packaged $APP"
