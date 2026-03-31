#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "Usage: $0 <version> <output-dir> [build-number]" >&2
  exit 1
fi

VERSION="$1"
OUTPUT_DIR="$2"
BUILD_NUMBER="${3:-${GITHUB_RUN_NUMBER:-1}}"
WORKDIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA_PATH="$WORKDIR/.xcode-derived-data-release"
SOURCE_PACKAGES_DIR="$WORKDIR/.xcode-source-packages"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Release/Lingobar.app"
STAGING_DIR="$OUTPUT_DIR/dmg-staging"
DMG_NAME="Lingobar-v${VERSION}-unsigned.dmg"
DMG_PATH="$OUTPUT_DIR/$DMG_NAME"

mkdir -p "$OUTPUT_DIR"
rm -rf "$DERIVED_DATA_PATH" "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$STAGING_DIR"

xcodebuild build \
  -project "$WORKDIR/Lingobar.xcodeproj" \
  -scheme Lingobar \
  -configuration Release \
  -destination 'platform=macOS' \
  -clonedSourcePackagesDirPath "$SOURCE_PACKAGES_DIR" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" >&2

cp -R "$APP_PATH" "$STAGING_DIR/Lingobar.app"

RW_DMG="$OUTPUT_DIR/_rw.dmg"
MOUNT_DIR="$OUTPUT_DIR/_dmg_mount"
rm -f "$RW_DMG"
mkdir -p "$MOUNT_DIR"
hdiutil create -volname "Lingobar" -size 200m -fs HFS+ -layout NONE "$RW_DMG" >/dev/null
hdiutil attach "$RW_DMG" -nobrowse -readwrite -mountpoint "$MOUNT_DIR" >/dev/null
cp -R "$STAGING_DIR/Lingobar.app" "$MOUNT_DIR/"
ln -s /Applications "$MOUNT_DIR/Applications"
hdiutil detach "$MOUNT_DIR" -quiet
hdiutil convert "$RW_DMG" -format UDZO -o "$DMG_PATH" -ov >/dev/null
rm -f "$RW_DMG"

printf '%s\n' "$DMG_PATH"
