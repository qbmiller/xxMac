#!/bin/bash

set -euo pipefail

APP_NAME="${APP_NAME:-xxMac}"
APP_BUNDLE="${APP_NAME}.app"
SKIP_BUILD="${SKIP_BUILD:-0}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-qbmiller}"
GH_BIN="${GH_BIN:-gh}"
PUBLISH_GITHUB_RELEASE="${PUBLISH_GITHUB_RELEASE:-}"
GITHUB_RELEASE_TITLE="${GITHUB_RELEASE_TITLE:-}"
GITHUB_RELEASE_NOTES="${GITHUB_RELEASE_NOTES:-}"
GITHUB_RELEASE_CONFIRM="${GITHUB_RELEASE_CONFIRM:-}"
RELEASE_TAG="${RELEASE_TAG:-}"
RELEASE_NOTES_FILE=""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFO_PLIST="${SCRIPT_DIR}/Sources/xxMac/Info.plist"
APP_PATH="${SCRIPT_DIR}/${APP_BUNDLE}"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/${APP_NAME}.dmg.XXXXXX")"

cleanup() {
  rm -rf "$STAGING_DIR"
  if [[ -n "$RELEASE_NOTES_FILE" ]]; then
    rm -f "$RELEASE_NOTES_FILE"
  fi
}
trap cleanup EXIT

edit_release_notes() {
  local editor_command
  local -a editor_parts

  editor_command="${VISUAL:-${EDITOR:-vi}}"
  read -r -a editor_parts <<< "$editor_command"

  if [[ "${#editor_parts[@]}" -eq 0 ]] || ! command -v "${editor_parts[0]}" >/dev/null 2>&1; then
    echo "Release notes editor not found: $editor_command"
    echo "Set VISUAL or EDITOR to an available editor, for example: EDITOR='code --wait'"
    return 1
  fi

  echo "Opening release notes in: $editor_command"
  "${editor_parts[@]}" "$RELEASE_NOTES_FILE"
}

cd "$SCRIPT_DIR"

if [[ ! -f "$INFO_PLIST" ]]; then
  echo "Missing Info.plist: $INFO_PLIST"
  exit 1
fi

if [[ -z "$SIGNING_IDENTITY" || "$SIGNING_IDENTITY" == "-" ]]; then
  echo "Missing fixed SIGNING_IDENTITY for DMG publishing."
  echo 'Example: SIGNING_IDENTITY="qbmiller" bash publish_dmg.sh'
  exit 1
fi

CURRENT_VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST")"
CURRENT_BUILD="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INFO_PLIST")"
RELEASE_DATE="$(date +%Y-%m-%d)"

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

if [[ -z "$PUBLISH_GITHUB_RELEASE" ]]; then
  read -r -p "Create GitHub Release after DMG verification? [y/N] " PUBLISH_GITHUB_RELEASE
fi

case "$PUBLISH_GITHUB_RELEASE" in
  y|Y|yes|Yes|YES|1|true|TRUE)
    PUBLISH_GITHUB_RELEASE=1
    ;;
  *)
    PUBLISH_GITHUB_RELEASE=0
    ;;
esac

if [[ "$PUBLISH_GITHUB_RELEASE" == "1" ]]; then
  if ! command -v "$GH_BIN" >/dev/null 2>&1; then
    echo "GitHub CLI not found: $GH_BIN"
    echo "Install gh first, then run: gh auth login -h github.com"
    exit 1
  fi

  if ! "$GH_BIN" auth status >/dev/null 2>&1; then
    echo "GitHub CLI is not authenticated."
    echo "Run: gh auth login -h github.com"
    exit 1
  fi

  RELEASE_TAG="${RELEASE_TAG:-$RELEASE_VERSION}"
  DEFAULT_RELEASE_TITLE="${APP_NAME} ${RELEASE_VERSION}"
  if [[ -z "$GITHUB_RELEASE_TITLE" ]]; then
    read -r -p "Release title [${DEFAULT_RELEASE_TITLE}]: " GITHUB_RELEASE_TITLE
    GITHUB_RELEASE_TITLE="${GITHUB_RELEASE_TITLE:-$DEFAULT_RELEASE_TITLE}"
  fi

  RELEASE_NOTES_FILE="$(mktemp "${TMPDIR:-/tmp}/${APP_NAME}.release-notes.XXXXXX")"
  if [[ -n "$GITHUB_RELEASE_NOTES" ]]; then
    printf "%s\n" "$GITHUB_RELEASE_NOTES" > "$RELEASE_NOTES_FILE"
  else
    while true; do
      edit_release_notes

      echo ""
      echo "Release notes preview:"
      if [[ -s "$RELEASE_NOTES_FILE" ]]; then
        sed 's/^/  /' "$RELEASE_NOTES_FILE"
      else
        echo "  (empty)"
      fi

      read -r -p "Use these release notes? [y/e/N] " RELEASE_NOTES_CONFIRM
      case "$RELEASE_NOTES_CONFIRM" in
        y|Y|yes|Yes|YES)
          break
          ;;
        e|E|edit|Edit|EDIT)
          ;;
        *)
          echo "GitHub Release cancelled. DMG build will continue."
          PUBLISH_GITHUB_RELEASE=0
          break
          ;;
      esac
    done
  fi
fi

DMG_NAME="${DMG_NAME:-${APP_NAME}-${RELEASE_VERSION}.dmg}"
VOLUME_NAME="${VOLUME_NAME:-${APP_NAME} ${RELEASE_VERSION}}"
DMG_PATH="${SCRIPT_DIR}/${DMG_NAME}"

echo "Release version: $RELEASE_VERSION"
echo "Release date: $RELEASE_DATE"
echo "Version source: $INFO_PLIST"

if [[ "$RELEASE_VERSION" != "$CURRENT_VERSION" || "$RELEASE_VERSION" != "$CURRENT_BUILD" ]]; then
  echo "Update Info.plist version..."
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $RELEASE_VERSION" "$INFO_PLIST"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $RELEASE_VERSION" "$INFO_PLIST"
fi

if /usr/libexec/PlistBuddy -c "Print :XXLastUpdated" "$INFO_PLIST" >/dev/null 2>&1; then
  /usr/libexec/PlistBuddy -c "Set :XXLastUpdated $RELEASE_DATE" "$INFO_PLIST"
else
  /usr/libexec/PlistBuddy -c "Add :XXLastUpdated string $RELEASE_DATE" "$INFO_PLIST"
fi

if [[ "$SKIP_BUILD" != "1" ]]; then
  echo "1) Build app bundle..."
  REQUIRE_SIGNING_IDENTITY=1 SIGNING_IDENTITY="$SIGNING_IDENTITY" bash bundle_app.sh
else
  echo "1) Skip build; use existing ${APP_BUNDLE}."
  echo "   Note: existing ${APP_BUNDLE} may still contain the previous version if it was built before this prompt."
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "Missing ${APP_BUNDLE}. Run bash bundle_app.sh first, or set SKIP_BUILD=0."
  exit 1
fi

echo "Verify app signature identity..."
SIGNATURE_INFO="$(codesign -dv --verbose=4 "$APP_PATH" 2>&1)"
if [[ "$SIGNATURE_INFO" == *"Signature=adhoc"* ]]; then
  echo "App is ad-hoc signed, expected fixed identity: $SIGNING_IDENTITY"
  echo "$SIGNATURE_INFO"
  exit 1
fi
if ! codesign -d -r- "$APP_PATH" 2>&1 | grep -q "certificate leaf"; then
  echo "App signature does not contain a certificate leaf requirement."
  codesign -d -r- "$APP_PATH" 2>&1 || true
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
echo "Install note for locally signed builds:"
echo "  xattr -cr /Applications/${APP_BUNDLE}"

if [[ "$PUBLISH_GITHUB_RELEASE" == "1" ]]; then
  echo ""
  echo "GitHub Release summary:"
  echo "  Tag: $RELEASE_TAG"
  echo "  Title: $GITHUB_RELEASE_TITLE"
  echo "  Asset: $DMG_PATH"
  echo "  Notes:"
  sed 's/^/    /' "$RELEASE_NOTES_FILE"
  echo "  Source tag: existing tag, or the latest default branch when the tag does not exist"
  echo "  Git commit/push: not performed by this script"

  if [[ -z "$GITHUB_RELEASE_CONFIRM" ]]; then
    read -r -p "Publish this GitHub Release now? [y/N] " GITHUB_RELEASE_CONFIRM
  fi

  case "$GITHUB_RELEASE_CONFIRM" in
    y|Y|yes|Yes|YES|1|true|TRUE)
      echo "5) Create GitHub Release and upload DMG..."
      "$GH_BIN" release create "$RELEASE_TAG" "$DMG_PATH" \
        --title "$GITHUB_RELEASE_TITLE" \
        --notes-file "$RELEASE_NOTES_FILE"
      echo "GitHub Release published: $RELEASE_TAG"
      ;;
    *)
      echo "GitHub Release skipped. DMG remains at: $DMG_PATH"
      ;;
  esac
fi
