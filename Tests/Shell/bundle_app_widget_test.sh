#!/bin/bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

assert_contains() {
    local file="$1"
    local expected="$2"
    grep -Fq -- "$expected" "$file" || fail "Expected '$expected' in $file"
}

make_fixture() {
    local fixture="$1"
    mkdir -p "$fixture/bin" "$fixture/Sources/xxMac" "$fixture/Resources"
    mkdir -p "$fixture/TodoWidget/TodoWidgetExtension"
    cp "$REPO_ROOT/bundle_app.sh" "$fixture/"
    cp "$REPO_ROOT/Sources/xxMac/Info.plist" "$fixture/Sources/xxMac/"
    cp "$REPO_ROOT/xxMac.entitlements" "$fixture/"
    cp "$REPO_ROOT/TodoWidget/TodoWidgetExtension/TodoWidgetExtension.entitlements" \
        "$fixture/TodoWidget/TodoWidgetExtension/"

    cat > "$fixture/bin/swift" <<'SCRIPT'
#!/bin/bash
set -e
echo "swift $*" >> "$CALL_LOG"
mkdir -p .build/arm64-apple-macosx/debug
printf '#!/bin/bash\n' > .build/arm64-apple-macosx/debug/xxMac
chmod +x .build/arm64-apple-macosx/debug/xxMac
SCRIPT

    cat > "$fixture/bin/xcodebuild" <<'SCRIPT'
#!/bin/bash
set -e
echo "xcodebuild $*" >> "$CALL_LOG"
if [ "${OMIT_WIDGET_PRODUCT:-0}" = "1" ]; then
    exit 0
fi
product=".build/TodoWidgetDerivedData/Build/Products/Release/TodoWidgetExtension.appex"
mkdir -p "$product/Contents/MacOS"
printf '#!/bin/bash\n' > "$product/Contents/MacOS/TodoWidgetExtension"
chmod +x "$product/Contents/MacOS/TodoWidgetExtension"
cat > "$product/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.xiaomi318.xxMac.TodoWidget</string>
<key>NSExtension</key><dict><key>NSExtensionPointIdentifier</key><string>com.apple.widgetkit-extension</string></dict>
</dict></plist>
PLIST
SCRIPT

    cat > "$fixture/bin/codesign" <<'SCRIPT'
#!/bin/bash
set -e
echo "codesign $*" >> "$CALL_LOG"
if [[ " $* " == *" -d "* ]]; then
    target="${!#}"
    if [[ "$target" == *.appex ]]; then
        cat >&2 <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>com.apple.security.app-sandbox</key><true/>
<key>com.apple.security.temporary-exception.files.home-relative-path.read-write</key><array><string>/Library/Application Support/xxMac/Widget/</string></array>
</dict></plist>
PLIST
    else
        cat >&2 <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>com.apple.security.app-sandbox</key><false/>
</dict></plist>
PLIST
    fi
fi
SCRIPT

    cat > "$fixture/bin/pgrep" <<'SCRIPT'
#!/bin/bash
echo "pgrep $*" >> "$CALL_LOG"
exit 1
SCRIPT

    cat > "$fixture/bin/killall" <<'SCRIPT'
#!/bin/bash
echo "killall $*" >> "$CALL_LOG"
SCRIPT

    cat > "$fixture/bin/open" <<'SCRIPT'
#!/bin/bash
echo "open $*" >> "$CALL_LOG"
SCRIPT

    chmod +x "$fixture/bin/swift" "$fixture/bin/xcodebuild" "$fixture/bin/codesign" \
        "$fixture/bin/pgrep" "$fixture/bin/killall" "$fixture/bin/open"
}

run_bundle() {
    local fixture="$1"
    shift
    (
        cd "$fixture"
        printf 'n\n' | env \
            PATH="$fixture/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
            CALL_LOG="$fixture/calls.log" \
            SIGNING_IDENTITY="Test Identity" \
            REQUIRE_SIGNING_IDENTITY=1 \
            "$@" \
            bash bundle_app.sh
    )
}

run_install() {
    local fixture="$1"
    mkdir -p "$fixture/Applications"
    (
        cd "$fixture"
        env \
            PATH="$fixture/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
            CALL_LOG="$fixture/calls.log" \
            SIGNING_IDENTITY="Test Identity" \
            REQUIRE_SIGNING_IDENTITY=1 \
            INSTALL_TO_APPLICATIONS=1 \
            APPLICATIONS_APP_PATH="$fixture/Applications/xxMac.app" \
            bash bundle_app.sh
    )
}

SUCCESS_FIXTURE="$TEST_ROOT/success"
make_fixture "$SUCCESS_FIXTURE"
run_bundle "$SUCCESS_FIXTURE"

assert_contains "$SUCCESS_FIXTURE/calls.log" \
    "xcodebuild -project TodoWidget/TodoWidget.xcodeproj -scheme TodoWidgetExtension"
[ -d "$SUCCESS_FIXTURE/xxMac.app/Contents/PlugIns/TodoWidgetExtension.appex" ] || \
    fail "Widget extension was not embedded"
assert_contains "$SUCCESS_FIXTURE/calls.log" \
    "--entitlements TodoWidget/TodoWidgetExtension/TodoWidgetExtension.entitlements xxMac.app/Contents/PlugIns/TodoWidgetExtension.appex"
assert_contains "$SUCCESS_FIXTURE/calls.log" \
    "--entitlements xxMac.entitlements xxMac.app"
assert_contains "$SUCCESS_FIXTURE/TodoWidget/TodoWidgetExtension/TodoWidgetExtension.entitlements" \
    "com.apple.security.temporary-exception.files.home-relative-path.read-write"
assert_contains "$SUCCESS_FIXTURE/TodoWidget/TodoWidgetExtension/TodoWidgetExtension.entitlements" \
    "/Library/Application Support/xxMac/Widget/"

extension_sign_line="$(grep -n -- '--entitlements TodoWidget/TodoWidgetExtension/TodoWidgetExtension.entitlements' "$SUCCESS_FIXTURE/calls.log" | head -1 | cut -d: -f1)"
host_sign_line="$(grep -n -- '--entitlements xxMac.entitlements' "$SUCCESS_FIXTURE/calls.log" | head -1 | cut -d: -f1)"
if [ -z "$extension_sign_line" ] || [ -z "$host_sign_line" ] || \
   [ "$extension_sign_line" -ge "$host_sign_line" ]; then
    fail "Extension must be signed before the host app"
fi

if grep -Fq -- "killall TodoWidgetExtension" "$SUCCESS_FIXTURE/calls.log"; then
    fail "Widget extension must not be reloaded when installation is skipped"
fi

assert_contains "$REPO_ROOT/bundle_app.sh" \
    'APPLICATIONS_APP_PATH="${APPLICATIONS_APP_PATH:-/Applications/$APP_BUNDLE}"'

INSTALL_FIXTURE="$TEST_ROOT/install"
make_fixture "$INSTALL_FIXTURE"
run_install "$INSTALL_FIXTURE"
[ -d "$INSTALL_FIXTURE/Applications/xxMac.app" ] || \
    fail "Installed app was not copied to the configured Applications path"
assert_contains "$INSTALL_FIXTURE/calls.log" "killall TodoWidgetExtension"
assert_contains "$INSTALL_FIXTURE/calls.log" \
    "open $INSTALL_FIXTURE/Applications/xxMac.app"

MISSING_FIXTURE="$TEST_ROOT/missing-product"
make_fixture "$MISSING_FIXTURE"
if run_bundle "$MISSING_FIXTURE" OMIT_WIDGET_PRODUCT=1 >/dev/null 2>&1; then
    fail "Bundle should fail when the widget product is missing"
fi

BAD_ENTITLEMENT_FIXTURE="$TEST_ROOT/bad-entitlement"
make_fixture "$BAD_ENTITLEMENT_FIXTURE"
sed -i '' 's#/Library/Application Support/xxMac/Widget/#/Library/Application Support/invalid/#' \
    "$BAD_ENTITLEMENT_FIXTURE/TodoWidget/TodoWidgetExtension/TodoWidgetExtension.entitlements"
if run_bundle "$BAD_ENTITLEMENT_FIXTURE" >/dev/null 2>&1; then
    fail "Bundle should fail when the widget shared-directory entitlement is missing"
fi

echo "bundle_app_widget_test: PASS"
