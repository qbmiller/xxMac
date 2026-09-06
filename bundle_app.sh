#!/bin/bash

APP_NAME="xxMac"
BUILD_DIR=".build/arm64-apple-macosx/debug"
APP_BUNDLE="$APP_NAME.app"
APPLICATIONS_APP_PATH="${APPLICATIONS_APP_PATH:-/Applications/$APP_BUNDLE}"
APP_ENTITLEMENTS="xxMac.entitlements"
WIDGET_SHARED_DIRECTORY_EXCEPTION="/Library/Application Support/xxMac/Widget/"
WIDGET_PROJECT="TodoWidget/TodoWidget.xcodeproj"
WIDGET_SCHEME="TodoWidgetExtension"
WIDGET_PROCESS_NAME="TodoWidgetExtension"
WIDGET_DERIVED_DATA=".build/TodoWidgetDerivedData"
WIDGET_PRODUCT="$WIDGET_DERIVED_DATA/Build/Products/Release/TodoWidgetExtension.appex"
WIDGET_ENTITLEMENTS="TodoWidget/TodoWidgetExtension/TodoWidgetExtension.entitlements"
EMBEDDED_WIDGET="$APP_BUNDLE/Contents/PlugIns/TodoWidgetExtension.appex"

# Signing Identity (Default: "qbmiller" for stable local signing)
# To use your Apple ID, create a certificate in Xcode (Settings > Accounts > Manage Certificates)
# Then run: security find-identity -v -p codesigning
# And set SIGNING_IDENTITY to the name of your certificate, e.g.:
# SIGNING_IDENTITY="Apple Development: Your Name (XXXXXXXXXX)"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-qbmiller}"
REQUIRE_SIGNING_IDENTITY="${REQUIRE_SIGNING_IDENTITY:-1}"

if [ "$REQUIRE_SIGNING_IDENTITY" = "1" ] && [ "$SIGNING_IDENTITY" = "-" ]; then
    echo "REQUIRE_SIGNING_IDENTITY=1 requires a fixed SIGNING_IDENTITY."
    exit 1
fi

if [ ! -f "$APP_ENTITLEMENTS" ]; then
    echo "Host entitlement file is missing: $APP_ENTITLEMENTS"
    exit 1
fi
if [ ! -f "$WIDGET_ENTITLEMENTS" ] || ! grep -Fq "$WIDGET_SHARED_DIRECTORY_EXCEPTION" "$WIDGET_ENTITLEMENTS"; then
    echo "Widget entitlement file is missing shared-directory access: $WIDGET_SHARED_DIRECTORY_EXCEPTION"
    exit 1
fi
if ! /usr/libexec/PlistBuddy -c "Print :com.apple.security.app-sandbox" "$WIDGET_ENTITLEMENTS" 2>/dev/null | grep -qx "true"; then
    echo "Widget entitlement file must enable the App Sandbox."
    exit 1
fi

# 1. Build the host and widget extension
echo "Building..."
swift build || { echo "Build failed"; exit 1; }

APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Sources/xxMac/Info.plist)"
APP_BUILD_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Sources/xxMac/Info.plist)"

echo "Building Todo Widget Extension..."
xcodebuild \
    -project "$WIDGET_PROJECT" \
    -scheme "$WIDGET_SCHEME" \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$WIDGET_DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO \
    MARKETING_VERSION="$APP_VERSION" \
    CURRENT_PROJECT_VERSION="$APP_BUILD_VERSION" \
    build || { echo "Todo Widget Extension build failed"; exit 1; }

if [ ! -d "$WIDGET_PRODUCT" ]; then
    echo "Todo Widget Extension product not found: $WIDGET_PRODUCT"
    exit 1
fi

# 2. Create Directory Structure
echo "Creating App Bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
mkdir -p "$APP_BUNDLE/Contents/PlugIns"

# 3. Copy Binary
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/"

# 4. Copy Info.plist
cp "Sources/xxMac/Info.plist" "$APP_BUNDLE/Contents/"

# 5. Copy Resources (Icon and localizations)
if [ -d "Resources" ]; then
    cp -R Resources/. "$APP_BUNDLE/Contents/Resources/"
fi

# 6. Embed the widget extension
cp -R "$WIDGET_PRODUCT" "$EMBEDDED_WIDGET"

# 7. Make binaries executable
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$EMBEDDED_WIDGET/Contents/MacOS/TodoWidgetExtension"

sign_bundles() {
    local identity="$1"
    codesign --force --verbose --sign "$identity" \
        --entitlements "$WIDGET_ENTITLEMENTS" "$EMBEDDED_WIDGET" || return 1
    codesign --force --verbose --sign "$identity" \
        --entitlements "$APP_ENTITLEMENTS" "$APP_BUNDLE" || return 1
}

# 8. Code sign nested code first, then the host app
echo "Code signing with identity: $SIGNING_IDENTITY"
sign_bundles "$SIGNING_IDENTITY" || {
    echo "Warning: Code signing failed with identity: $SIGNING_IDENTITY"
    if [ "$REQUIRE_SIGNING_IDENTITY" = "1" ]; then
        echo "Fixed signing is required; refusing to fall back to ad-hoc signing."
        exit 1
    fi
    if [ "$SIGNING_IDENTITY" != "-" ]; then
        echo "Falling back to ad-hoc signing (-)..."
        sign_bundles - || { echo "Ad-hoc signing failed."; exit 1; }
    else
        echo "Code signing failed completely."
        exit 1
    fi
}

# 9. Verify nested signatures and signed entitlements
codesign --verify --strict --verbose=2 "$EMBEDDED_WIDGET" || exit 1
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE" || exit 1

SIGNED_APP_ENTITLEMENTS="$(mktemp -t xxmac-app-entitlements).plist"
SIGNED_WIDGET_ENTITLEMENTS="$(mktemp -t xxmac-widget-entitlements).plist"
codesign -d --entitlements :- "$APP_BUNDLE" 2>&1 | sed -n '/<?xml/,$p' > "$SIGNED_APP_ENTITLEMENTS"
codesign -d --entitlements :- "$EMBEDDED_WIDGET" 2>&1 | sed -n '/<?xml/,$p' > "$SIGNED_WIDGET_ENTITLEMENTS"

if ! grep -Fq "$WIDGET_SHARED_DIRECTORY_EXCEPTION" "$SIGNED_WIDGET_ENTITLEMENTS"; then
    echo "Signed widget is missing shared-directory access: $WIDGET_SHARED_DIRECTORY_EXCEPTION"
    rm -f "$SIGNED_APP_ENTITLEMENTS" "$SIGNED_WIDGET_ENTITLEMENTS"
    exit 1
fi
if ! /usr/libexec/PlistBuddy -c "Print :com.apple.security.app-sandbox" "$SIGNED_WIDGET_ENTITLEMENTS" 2>/dev/null | grep -qx "true"; then
    echo "Signed widget is missing the App Sandbox entitlement."
    rm -f "$SIGNED_APP_ENTITLEMENTS" "$SIGNED_WIDGET_ENTITLEMENTS"
    exit 1
fi
rm -f "$SIGNED_APP_ENTITLEMENTS" "$SIGNED_WIDGET_ENTITLEMENTS"

echo "Success! $APP_BUNDLE created."
echo "You can run it by: open $APP_BUNDLE"
echo ""
echo "⚠️  IMPORTANT: On first run, macOS will prompt for permissions:"
echo "   1. System Settings > Privacy & Security > Accessibility"
echo "   2. Add 'xxMac' to the allowed apps list"
echo "   3. Restart the app for global hotkeys to work"

# Install to /Applications only after explicit confirmation. The environment
# variable remains available for scripts that intentionally opt into this step.
INSTALL_RESPONSE=""
if [ "${INSTALL_TO_APPLICATIONS:-0}" = "1" ]; then
    INSTALL_RESPONSE="y"
    echo "INSTALL_TO_APPLICATIONS=1，自动确认覆盖 ${APPLICATIONS_APP_PATH}。"
else
    printf "是否覆盖原文件 %s？[y/N] " "$APPLICATIONS_APP_PATH"
    read -r INSTALL_RESPONSE
fi

case "$INSTALL_RESPONSE" in
    y|Y|yes|Yes|YES)
        echo "准备替换 $APPLICATIONS_APP_PATH..."

        # Ask the running app to quit first, then wait before touching its bundle.
        if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
            echo "正在关闭当前已启动的 $APP_NAME..."
            osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true

            WAIT_SECONDS=0
            while pgrep -x "$APP_NAME" >/dev/null 2>&1 && [ "$WAIT_SECONDS" -lt 10 ]; do
                sleep 0.5
                WAIT_SECONDS=$((WAIT_SECONDS + 1))
            done

            if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
                echo "应用未正常退出，强制关闭 $APP_NAME..."
                killall "$APP_NAME" 2>/dev/null || true
                sleep 1
            fi

            if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
                echo "无法关闭当前运行中的 ${APP_NAME}，已取消覆盖。"
                exit 1
            fi
        fi

        if ! rm -rf "$APPLICATIONS_APP_PATH"; then
            echo "删除旧应用失败，已取消覆盖：$APPLICATIONS_APP_PATH"
            exit 1
        fi
        if ! cp -R "$APP_BUNDLE" "$APPLICATIONS_APP_PATH"; then
            echo "复制到 $APPLICATIONS_APP_PATH 失败。"
            exit 1
        fi

        echo "正在重新加载待办小组件..."
        killall "$WIDGET_PROCESS_NAME" 2>/dev/null || true

        if ! open "$APPLICATIONS_APP_PATH"; then
            echo "应用已替换，但重新打开失败：$APPLICATIONS_APP_PATH"
            exit 1
        fi

        echo "已替换为新应用并打开：$APPLICATIONS_APP_PATH"
        ;;
    *)
        echo "已保留生成的 ${APP_BUNDLE}，未覆盖 ${APPLICATIONS_APP_PATH}。"
        ;;
esac
