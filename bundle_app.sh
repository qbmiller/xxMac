#!/bin/bash

APP_NAME="xxMac"
BUILD_DIR=".build/arm64-apple-macosx/debug"
APP_BUNDLE="$APP_NAME.app"

# Signing Identity (Default: "-" for ad-hoc signing)
# To use your Apple ID, create a certificate in Xcode (Settings > Accounts > Manage Certificates)
# Then run: security find-identity -v -p codesigning
# And set SIGNING_IDENTITY to the name of your certificate, e.g.:
# SIGNING_IDENTITY="Apple Development: Your Name (XXXXXXXXXX)"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"

# 1. Build
echo "Building..."
swift build || { echo "Build failed"; exit 1; }

# 2. Create Directory Structure
echo "Creating App Bundle..."
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# 3. Copy Binary
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/"

# 4. Copy Info.plist
cp "Sources/xxMac/Info.plist" "$APP_BUNDLE/Contents/"

# 5. Copy Resources (Icon and localizations)
if [ -d "Resources" ]; then
    cp -R Resources/. "$APP_BUNDLE/Contents/Resources/"
fi

# 6. Make binary executable
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# 7. Code Sign the app (required for global hotkeys to work)
echo "Code signing with identity: $SIGNING_IDENTITY"
codesign --deep --force --verify --verbose --sign "$SIGNING_IDENTITY" --options runtime "$APP_BUNDLE" 2>/dev/null || {
    echo "Warning: Code signing failed with identity: $SIGNING_IDENTITY"
    if [ "$SIGNING_IDENTITY" != "-" ]; then
        echo "Falling back to ad-hoc signing (-)..."
        codesign --deep --force --verify --verbose --sign - "$APP_BUNDLE"
    else
        echo "Code signing failed completely."
        exit 1
    fi
}

echo "Success! $APP_BUNDLE created."
echo "You can run it by: open $APP_BUNDLE"
echo ""
echo "⚠️  IMPORTANT: On first run, macOS will prompt for permissions:"
echo "   1. System Settings > Privacy & Security > Accessibility"
echo "   2. Add 'xxMac' to the allowed apps list"
echo "   3. Restart the app for global hotkeys to work"
