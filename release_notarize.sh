#!/bin/bash

set -euo pipefail

APP_NAME="${APP_NAME:-xxMac}"
APP_BUNDLE="${APP_NAME}.app"
ZIP_PATH="${APP_NAME}.zip"

# Required for distribution.
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
KEYCHAIN_PROFILE="${KEYCHAIN_PROFILE:-}"

if [[ -z "$SIGNING_IDENTITY" ]]; then
  echo "Missing SIGNING_IDENTITY."
  echo 'Example: export SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)"'
  exit 1
fi

if [[ -z "$KEYCHAIN_PROFILE" ]]; then
  echo "Missing KEYCHAIN_PROFILE."
  echo 'Create one first: xcrun notarytool store-credentials "AC_PROFILE" --apple-id ... --team-id ... --password ...'
  echo 'Then: export KEYCHAIN_PROFILE="AC_PROFILE"'
  exit 1
fi

echo "1) Build app bundle with Developer ID signing..."
SIGNING_IDENTITY="$SIGNING_IDENTITY" bash bundle_app.sh

echo "2) Verify code signature..."
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
spctl --assess --type execute --verbose "$APP_BUNDLE" || true

echo "3) Create zip for notarization..."
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"

echo "4) Submit for notarization (wait until complete)..."
xcrun notarytool submit "$ZIP_PATH" \
  --keychain-profile "$KEYCHAIN_PROFILE" \
  --wait

echo "5) Staple ticket to app..."
xcrun stapler staple "$APP_BUNDLE"
xcrun stapler validate "$APP_BUNDLE"

echo "6) Recreate zip with stapled app..."
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"

echo ""
echo "Done."
echo "Distributable file: $ZIP_PATH"
echo "Recommended quick check:"
echo "  spctl --assess --type execute --verbose \"$APP_BUNDLE\""
