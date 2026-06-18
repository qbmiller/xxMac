#!/bin/bash

set -euo pipefail

APP_NAME="${APP_NAME:-xxMac}"
APP_BUNDLE="${APP_NAME}.app"
SKIP_BUILD="${SKIP_BUILD:-0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFO_PLIST="${SCRIPT_DIR}/Sources/xxMac/Info.plist"
APP_PATH="${SCRIPT_DIR}/${APP_BUNDLE}"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/${APP_NAME}.dmg.XXXXXX")"

cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

cd "$SCRIPT_DIR"

if [[ ! -f "$INFO_PLIST" ]]; then
  echo "Missing Info.plist: $INFO_PLIST"
  exit 1
fi

CURRENT_VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST")"
CURRENT_BUILD="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INFO_PLIST")"

echo "Current version: $CURRENT_VERSION"
echo "Current build: $CURRENT_BUILD"

if [[ -n "${VERSION:-}" ]]; then
  RELEASE_VERSION="$VERSION"
else
  read -r -p "Enter release version [${CURRENT_VERSION}]: " RELEASE_VERSION
  RELEASE_VERSION="${RELEASE_VERSION:-$CURRENT_VERSION}"
fi

if [[ ! "$RELEASE_VERSION" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
  echo "Invalid version: $RELEASE_VERSION"
  echo "Use numeric versions like 0.0.1 or 1.2.3."
  exit 1
fi

DMG_NAME="${DMG_NAME:-${APP_NAME}-${RELEASE_VERSION}.dmg}"
VOLUME_NAME="${VOLUME_NAME:-${APP_NAME} ${RELEASE_VERSION}}"
DMG_PATH="${SCRIPT_DIR}/${DMG_NAME}"

echo "Release version: $RELEASE_VERSION"
echo "Version source: $INFO_PLIST"

if [[ "$RELEASE_VERSION" != "$CURRENT_VERSION" || "$RELEASE_VERSION" != "$CURRENT_BUILD" ]]; then
  echo "Update Info.plist version..."
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $RELEASE_VERSION" "$INFO_PLIST"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $RELEASE_VERSION" "$INFO_PLIST"
fi

if [[ "$SKIP_BUILD" != "1" ]]; then
  echo "1) Build app bundle..."
  bash bundle_app.sh
else
  echo "1) Skip build; use existing ${APP_BUNDLE}."
  echo "   Note: existing ${APP_BUNDLE} may still contain the previous version if it was built before this prompt."
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "Missing ${APP_BUNDLE}. Run bash bundle_app.sh first, or set SKIP_BUILD=0."
  exit 1
fi

echo "2) Prepare DMG staging folder..."
ditto "$APP_PATH" "${STAGING_DIR}/${APP_BUNDLE}"
ln -s /Applications "${STAGING_DIR}/Applications"

echo "3) Create compressed DMG..."
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "4) Verify DMG..."
hdiutil verify "$DMG_PATH"

echo ""
echo "Done."
echo "DMG: $DMG_PATH"
echo "Version: $RELEASE_VERSION"
echo ""
echo "Install note for ad-hoc signed builds:"
echo "  xattr -cr /Applications/${APP_BUNDLE}"
