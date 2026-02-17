#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="Dict"
BUILD_DIR="$PROJECT_DIR/.build"
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"
DMG_PATH="$PROJECT_DIR/$APP_NAME.dmg"
VERSION=$(plutil -extract CFBundleShortVersionString raw "$PROJECT_DIR/Resources/Info.plist")

cleanup_dmg() {
    rm -f "$PROJECT_DIR/rw-$APP_NAME.dmg"
    if mount | grep -q "/Volumes/$APP_NAME"; then
        hdiutil detach "/Volumes/$APP_NAME" -force 2>/dev/null || true
    fi
}

echo "Building $APP_NAME v$VERSION..."
cd "$PROJECT_DIR"
swift build -c release

echo "Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/release/Dict" "$APP_BUNDLE/Contents/MacOS/Dict"
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/"
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"

# Code-sign the app bundle
# For distribution: set CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
# For notarization: also set NOTARY_PROFILE="your-keychain-profile"
SIGN_IDENTITY="${CODESIGN_IDENTITY:-Apple Development}"
ENTITLEMENTS="$PROJECT_DIR/Resources/Dict.entitlements"
if codesign --force --options runtime --sign "$SIGN_IDENTITY" --entitlements "$ENTITLEMENTS" --deep "$APP_BUNDLE" 2>/dev/null; then
    echo "Signed with: $SIGN_IDENTITY"
else
    echo "Warning: Code signing failed. Accessibility permissions will reset on each install."
fi

echo "App bundle created at: $APP_BUNDLE"

# Build DMG if --dmg flag is passed
if [[ "${1:-}" == "--dmg" ]]; then
    echo "Creating DMG..."
    trap cleanup_dmg EXIT
    rm -f "$DMG_PATH"

    # Generate DMG background image
    BACKGROUND="$PROJECT_DIR/Resources/dmg-background.png"
    if [[ ! -f "$BACKGROUND" ]]; then
        echo "Generating DMG background..."
        swift "$SCRIPT_DIR/generate-dmg-background.swift"
    fi

    # Create writable DMG with app + Applications link + background
    DMG_TMP="$PROJECT_DIR/.dmg-staging"
    DMG_RW="$PROJECT_DIR/rw-$APP_NAME.dmg"
    rm -rf "$DMG_TMP" "$DMG_RW"
    mkdir -p "$DMG_TMP"
    cp -R "$APP_BUNDLE" "$DMG_TMP/"
    ln -s /Applications "$DMG_TMP/Applications"

    mkdir -p "$DMG_TMP/.background"
    cp "$BACKGROUND" "$DMG_TMP/.background/bg.png"

    # Create writable HFS+ DMG (HFS+ supports hidden flags reliably)
    hdiutil create -volname "$APP_NAME" \
        -srcfolder "$DMG_TMP" \
        -ov -format UDRW \
        -fs HFS+ \
        "$DMG_RW"
    rm -rf "$DMG_TMP"

    # Mount writable DMG and style via AppleScript
    MOUNT_DIR=$(hdiutil attach -readwrite -noverify "$DMG_RW" | grep "/Volumes/" | sed 's/.*\/Volumes/\/Volumes/' | xargs)
    VOL_NAME=$(basename "$MOUNT_DIR")
    sleep 2

    # Hide extension on Dict.app
    SetFile -a E "$MOUNT_DIR/Dict.app" 2>/dev/null || true

    # Apply Finder view settings via AppleScript
    osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$VOL_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {200, 120, 1000, 570}
        set opts to the icon view options of container window
        set icon size of opts to 100
        set text size of opts to 12
        set arrangement of opts to not arranged
        set background picture of opts to file ".background:bg.png"
        set position of item "Dict.app" of container window to {200, 200}
        set position of item "Applications" of container window to {600, 200}
        close
        open
        update without registering applications
        delay 2
        close
    end tell
end tell
APPLESCRIPT

    # Wait for Finder to write .DS_Store
    sync
    sleep 2

    # Hide dotfiles and clean up .fseventsd
    chflags hidden "$MOUNT_DIR/.background" 2>/dev/null || true
    rm -rf "$MOUNT_DIR/.fseventsd" 2>/dev/null || true

    # Unmount and compress
    hdiutil detach "$MOUNT_DIR"
    hdiutil convert "$DMG_RW" -format UDZO -o "$DMG_PATH"
    rm -f "$DMG_RW"

    # Notarize if NOTARY_PROFILE is set
    # Setup (one-time): xcrun notarytool store-credentials "dict-notary" \
    #   --apple-id "your@email.com" --team-id "TEAMID" --password "app-specific-password"
    # Then: NOTARY_PROFILE="dict-notary" ./scripts/build.sh --dmg
    NOTARY_PROFILE="${NOTARY_PROFILE:-}"
    if [[ -n "$NOTARY_PROFILE" ]]; then
        echo "Notarizing DMG..."
        xcrun notarytool submit "$DMG_PATH" \
            --keychain-profile "$NOTARY_PROFILE" \
            --wait
        echo "Stapling notarization ticket..."
        xcrun stapler staple "$DMG_PATH"
        echo "Notarization complete."
    else
        echo "Skipping notarization (set NOTARY_PROFILE to enable)."
    fi

    echo "DMG created at: $DMG_PATH"
fi

echo "Done!"
echo "Run with: open $APP_BUNDLE"
