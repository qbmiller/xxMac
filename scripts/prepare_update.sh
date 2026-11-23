#!/bin/bash
# Produce local Sparkle release assets. This script never uploads or publishes.
set -euo pipefail
cd "$(dirname "$0")/.."
APP_PATH="${UPDATE_APP_PATH:-xxMac.app}"
UPDATE_OUTPUT_DIR="${UPDATE_OUTPUT_DIR:-.build/update-release}"
if [[ -z "${SPARKLE_TOOLS_DIR:-}" ]]; then
    for candidate in .build/artifacts/*/Sparkle/bin; do
        if [[ -x "$candidate/generate_appcast" ]]; then
            SPARKLE_TOOLS_DIR="$candidate"
            break
        fi
    done
fi
: "${SPARKLE_TOOLS_DIR:?Build first or set SPARKLE_TOOLS_DIR to the official Sparkle bin directory}"

if [[ ! -x "$SPARKLE_TOOLS_DIR/generate_appcast" ]]; then
    echo "Missing Sparkle generate_appcast: $SPARKLE_TOOLS_DIR" >&2
    exit 1
fi

# Check configuration BEFORE replacing any previous local update assets.
python3 - "$APP_PATH/Contents/Info.plist" <<'PY'
import base64, plistlib, sys, urllib.parse
with open(sys.argv[1], 'rb') as f:
    info = plistlib.load(f)
try:
    key = base64.b64decode(info.get('SUPublicEDKey', ''), validate=True)
except ValueError:
    key = b''
feed = urllib.parse.urlparse(info.get('SUFeedURL', ''))
if len(key) != 32 or feed.scheme != 'https' or not feed.hostname:
    sys.exit('App must contain a 32-byte SUPublicEDKey and HTTPS SUFeedURL. Rebuild with SPARKLE_PUBLIC_ED_KEY and SPARKLE_FEED_URL.')
PY
codesign --verify --deep --strict "$APP_PATH"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")
if [[ ! "$VERSION" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
    echo "Expected a numeric app version: $VERSION" >&2
    exit 1
fi
# Keep the download URL versioned even when appcast.xml uses /latest/download/.
DOWNLOAD_PREFIX="${SPARKLE_DOWNLOAD_URL_PREFIX:-https://github.com/qbmiller/xxMac/releases/download/${RELEASE_TAG:-$VERSION}/}"
if [[ "$DOWNLOAD_PREFIX" != https://* ]]; then
    echo "SPARKLE_DOWNLOAD_URL_PREFIX must use HTTPS" >&2
    exit 1
fi
STAGING_DIR=$(mktemp -d "${TMPDIR:-/tmp}/xxmac-update.XXXXXX")
trap 'rm -rf "$STAGING_DIR"' EXIT
ARCHIVE_NAME="xxMac-${VERSION}.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$STAGING_DIR/$ARCHIVE_NAME"
ARGS=(--account "${SPARKLE_KEY_ACCOUNT:-xxMac}" --download-url-prefix "$DOWNLOAD_PREFIX" --maximum-versions 1 --maximum-deltas 0)
if [[ -n "${SPARKLE_PRIVATE_KEY_FILE:-}" ]]; then
    ARGS+=(--ed-key-file "$SPARKLE_PRIVATE_KEY_FILE")
fi
"$SPARKLE_TOOLS_DIR/generate_appcast" "${ARGS[@]}" "$STAGING_DIR"
python3 - "$STAGING_DIR/appcast.xml" "$ARCHIVE_NAME" <<'PY'
import sys, xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
items = root.findall('./channel/item')
if len(items) != 1:
    sys.exit('Expected exactly one signed update in appcast.xml')
enclosure = items[0].find('enclosure')
if enclosure is None or not enclosure.get('{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature'):
    sys.exit('Appcast has no Ed25519 signature; nothing will be published')
if not enclosure.get('url', '').endswith('/' + sys.argv[2]):
    sys.exit('Appcast download URL does not match the versioned archive')
PY
mkdir -p "$UPDATE_OUTPUT_DIR"
cp "$STAGING_DIR/$ARCHIVE_NAME" "$UPDATE_OUTPUT_DIR/"
cp "$STAGING_DIR/appcast.xml" "$UPDATE_OUTPUT_DIR/"
echo "Prepared local update assets in $UPDATE_OUTPUT_DIR: $ARCHIVE_NAME, appcast.xml"
echo "Ready to upload both assets to the matching release. Keep your private key out of the repository."
