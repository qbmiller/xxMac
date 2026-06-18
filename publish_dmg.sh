#!/bin/bash

set -euo pipefail

APP_NAME="${APP_NAME:-xxMac}"
APP_BUNDLE="${APP_NAME}.app"
DMG_NAME="${DMG_NAME:-${APP_NAME}.dmg}"
VOLUME_NAME="${VOLUME_NAME:-${APP_NAME}}"
SKIP_BUILD="${SKIP_BUILD:-0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_PATH="${SCRIPT_DIR}/${APP_BUNDLE}"
DMG_PATH="${SCRIPT_DIR}/${DMG_NAME}"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/${APP_NAME}.dmg.XXXXXX")"

cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

cd "$SCRIPT_DIR"

if [[ "$SKIP_BUILD" != "1" ]]; then
  echo "1) Build app bundle..."
  bash bundle_app.sh
else
  echo "1) Skip build; use existing ${APP_BUNDLE}."
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
echo ""
echo "Install note for ad-hoc signed builds:"
echo "  xattr -cr /Applications/${APP_BUNDLE}"
