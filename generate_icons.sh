#!/bin/bash
ICON_SOURCE="icons8-火种-64.png"
ICONSET_DIR="xxMac.iconset"

if [ ! -f "$ICON_SOURCE" ]; then
    echo "Error: $ICON_SOURCE not found!"
    exit 1
fi

mkdir -p "$ICONSET_DIR"

echo "Generating iconset from $ICON_SOURCE..."

# Resizing using sips
sips -z 16 16     "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16.png"
sips -z 32 32     "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png"
sips -z 32 32     "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32.png"
sips -z 64 64     "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png"
sips -z 128 128   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128.png"
sips -z 256 256   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png"
sips -z 256 256   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256.png"
sips -z 512 512   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png"
sips -z 512 512   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512.png"
sips -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512@2x.png"

echo "Converting to icns..."
iconutil -c icns "$ICONSET_DIR" -o "Sources/xxMac/Resources/AppIcon.icns"

echo "Cleaning up..."
rm -rf "$ICONSET_DIR"

echo "Done! AppIcon.icns generated in Sources/xxMac/Resources/"
