#!/usr/bin/env bash
# create-dmg.sh
# Creates a signed, customized DMG for MiniNotes with background image and icon layout.
# Adapted from https://github.com/tw93/MiaoYan
#
# Usage:
#   ./scripts/create-dmg.sh <path-to-MiniNotes.app> <version> <signing-identity>
#
# Example:
#   ./scripts/create-dmg.sh \
#     ~/Library/Developer/Xcode/DerivedData/.../Release/MiniNotes.app \
#     1.2.3 \
#     "Developer ID Application: Your Name (TEAMID)"

set -euo pipefail

APP_PATH="${1:?Usage: $0 <path-to-MiniNotes.app> <version> <signing-identity>}"
VERSION="${2:?Missing version argument}"
SIGNING_IDENTITY="${3:?Missing signing identity argument}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

APP_NAME="MiniNotes"
VOL_NAME="${APP_NAME} v${VERSION}"
BACKGROUND_SRC="$PROJECT_DIR/assets/dmg-background.png"
BACKGROUND_NAME="dmg-background.png"

STAGING_DIR="$PROJECT_DIR/dist/dmg-staging"
TEMP_DMG="$PROJECT_DIR/dist/${APP_NAME}-v${VERSION}-temp.dmg"
OUTPUT_DMG="$PROJECT_DIR/dist/${APP_NAME}-v${VERSION}.dmg"

mkdir -p "$PROJECT_DIR/dist"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

cleanup_volumes() {
    local max_attempts=15
    local attempt=0
    while [[ $attempt -lt $max_attempts ]]; do
        local attached
        attached=$(hdiutil info 2>/dev/null | grep -E "\/Volumes\/${APP_NAME}" | awk '{print $1}' || true)
        [[ -z "$attached" ]] && break
        echo "Detaching existing volume: $attached"
        hdiutil detach "$attached" -force 2>/dev/null || true
        sleep 1
        (( attempt++ ))
    done
}

# ---------------------------------------------------------------------------
# Clean up previous artifacts
# ---------------------------------------------------------------------------

echo "==> Cleaning previous artifacts..."
cleanup_volumes
rm -rf "$STAGING_DIR" "$TEMP_DMG"

# ---------------------------------------------------------------------------
# Build staging directory
# ---------------------------------------------------------------------------

echo "==> Staging DMG contents..."
mkdir -p "$STAGING_DIR/.background"
cp -R "$APP_PATH" "$STAGING_DIR/${APP_NAME}.app"
ln -s /Applications "$STAGING_DIR/Applications"
cp "$BACKGROUND_SRC" "$STAGING_DIR/.background/$BACKGROUND_NAME"

# Disable Spotlight indexing in staging dir
mdutil -i off "$STAGING_DIR" >/dev/null 2>&1 || true

# ---------------------------------------------------------------------------
# Create read-write DMG
# ---------------------------------------------------------------------------

echo "==> Creating read-write DMG..."
MAX_RETRIES=3
RETRY=0
while [[ $RETRY -lt $MAX_RETRIES ]]; do
    if hdiutil create -quiet \
        -volname "$VOL_NAME" \
        -srcfolder "$STAGING_DIR" \
        -ov -format UDRW \
        "$TEMP_DMG"; then
        break
    fi
    (( RETRY++ ))
    echo "    Retry $RETRY/$MAX_RETRIES..."
    cleanup_volumes
    sleep 2
done

if [[ ! -f "$TEMP_DMG" ]]; then
    echo "ERROR: Failed to create DMG after $MAX_RETRIES attempts" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Mount and configure Finder layout via AppleScript
# ---------------------------------------------------------------------------

echo "==> Mounting DMG..."
ATTACH_OUTPUT="$(hdiutil attach -readwrite -noverify -noautoopen "$TEMP_DMG" 2>/dev/null)"
DEVICE="$(echo "$ATTACH_OUTPUT" | awk '/^\/dev\// { print $1; exit }')"
MOUNT_POINT="$(echo "$ATTACH_OUTPUT" | awk -F '\t' '/\/Volumes\// { print $NF; exit }')"
DISK_NAME="$(basename "$MOUNT_POINT")"

echo "==> Configuring Finder window layout..."
osascript >/dev/null <<APPLESCRIPT
tell application "Finder"
    tell disk "${DISK_NAME}"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {100, 100, 760, 520}

        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 120
        set text size of viewOptions to 14

        try
            set background picture of viewOptions to file ".background:${BACKGROUND_NAME}"
        end try

        set position of item "${APP_NAME}.app" of container window to {165, 260}
        set position of item "Applications" of container window to {495, 260}

        close
        open
        update without registering applications
        delay 2
    end tell
end tell
APPLESCRIPT

/bin/sync

echo "==> Detaching DMG..."
hdiutil detach "$DEVICE" -force

# ---------------------------------------------------------------------------
# Convert to compressed read-only DMG
# ---------------------------------------------------------------------------

echo "==> Converting to compressed DMG..."
rm -f "$OUTPUT_DMG"
hdiutil convert -quiet "$TEMP_DMG" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -ov -o "$OUTPUT_DMG"

rm -f "$TEMP_DMG"

# ---------------------------------------------------------------------------
# Sign the DMG
# ---------------------------------------------------------------------------

echo "==> Signing DMG..."
codesign --force \
    --sign "$SIGNING_IDENTITY" \
    "$OUTPUT_DMG"

codesign -v "$OUTPUT_DMG"

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------

rm -rf "$STAGING_DIR"

echo ""
echo "✓ DMG ready: $OUTPUT_DMG"
