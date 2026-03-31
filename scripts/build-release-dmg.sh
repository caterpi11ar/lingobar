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
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER"

cp -R "$APP_PATH" "$STAGING_DIR/Lingobar.app"

hdiutil create \
  -volname "Lingobar" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

printf '%s\n' "$DMG_PATH"
