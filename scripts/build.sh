#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="Dict"
BUILD_DIR="$PROJECT_DIR/.build"
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"
DMG_PATH="$PROJECT_DIR/$APP_NAME.dmg"
VERSION=$(plutil -extract CFBundleShortVersionString raw "$PROJECT_DIR/Resources/Info.plist")

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

# Code-sign so macOS preserves permissions across updates
SIGN_IDENTITY="${CODESIGN_IDENTITY:-Apple Development}"
if codesign --force --sign "$SIGN_IDENTITY" --deep "$APP_BUNDLE" 2>/dev/null; then
    echo "Signed with: $SIGN_IDENTITY"
else
    echo "Warning: Code signing failed. Accessibility permissions will reset on each install."
fi

echo "App bundle created at: $APP_BUNDLE"

# Build DMG if --dmg flag is passed
if [[ "${1:-}" == "--dmg" ]]; then
    echo "Creating DMG..."
    rm -f "$DMG_PATH"

    # Create temporary DMG directory
    DMG_TMP="$PROJECT_DIR/.dmg-staging"
    rm -rf "$DMG_TMP"
    mkdir -p "$DMG_TMP"
    cp -R "$APP_BUNDLE" "$DMG_TMP/"

    # Create Applications symlink for drag-to-install
    ln -s /Applications "$DMG_TMP/Applications"

    # Add instructions for unsigned app
    cat > "$DMG_TMP/READ ME FIRST.txt" <<'README'
Dict is not code-signed yet, so macOS may block it after download.

After dragging Dict to Applications, open Terminal and run:

    xattr -cr /Applications/Dict.app

Then open Dict normally. You only need to do this once.

Alternatively, right-click Dict.app → Open → click "Open" in the dialog.
README

    hdiutil create -volname "$APP_NAME" \
        -srcfolder "$DMG_TMP" \
        -ov -format UDZO \
        "$DMG_PATH"

    rm -rf "$DMG_TMP"
    echo "DMG created at: $DMG_PATH"
fi

echo "Done!"
echo "Run with: open $APP_BUNDLE"
