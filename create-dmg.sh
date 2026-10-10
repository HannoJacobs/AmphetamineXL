#!/bin/bash
set -euo pipefail

APP_NAME="AmphetamineXL"
BUNDLE_ID="com.hannojacobs.AmphetamineXL"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DMG_NAME="$SCRIPT_DIR/${APP_NAME}.dmg"
APP_BUNDLE="${APP_NAME}.app"
# Keep temporary app bundles out of Spotlight, even while packaging is running.
BUILD_DIR="$SCRIPT_DIR/build-release.noindex"

cleanup() {
    local status=$?
    trap - EXIT
    if ! rm -rf "$BUILD_DIR"; then
        echo "Error: Could not remove packaging directory: $BUILD_DIR" >&2
        if [ "$status" -eq 0 ]; then status=1; fi
    fi
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# An explicit build output avoids selecting another worktree's Release binary.
BINARY="${AMPHETAMINEXL_RELEASE_BINARY:-}"
if [ -z "$BINARY" ]; then
    BINARY=$(find ~/Library/Developer/Xcode/DerivedData -path "*/Release/${APP_NAME}" -type f 2>/dev/null | head -1)
fi

if [ -z "$BINARY" ] || [ ! -f "$BINARY" ]; then
    echo "Error: No Release build found."
    echo "Run: xcodebuild -scheme AmphetamineXL -configuration Release -destination 'platform=macOS' build"
    exit 1
fi

echo "Found binary: $BINARY"

# Clean previous build artifacts
rm -rf "$BUILD_DIR" "$DMG_NAME"
mkdir -p "$BUILD_DIR/$APP_BUNDLE/Contents/MacOS"
mkdir -p "$BUILD_DIR/$APP_BUNDLE/Contents/Resources"

# Copy binary
cp "$BINARY" "$BUILD_DIR/$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Copy app icon if present
if [ -f "$SCRIPT_DIR/AppIcon.icns" ]; then
    cp "$SCRIPT_DIR/AppIcon.icns" "$BUILD_DIR/$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    echo "Included app icon"
fi

# Create Info.plist
cat > "$BUILD_DIR/$APP_BUNDLE/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.hannojacobs.AmphetamineXL</string>
    <key>CFBundleName</key>
    <string>AmphetamineXL</string>
    <key>CFBundleDisplayName</key>
    <string>AmphetamineXL</string>
    <key>CFBundleExecutable</key>
    <string>AmphetamineXL</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>2.3.3</string>
    <key>CFBundleShortVersionString</key>
    <string>2.3.3</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
</dict>
</plist>
PLIST

echo "Created $APP_BUNDLE"

# Create staging with Applications symlink
DMG_STAGING="$BUILD_DIR/dmg-staging"
mkdir -p "$DMG_STAGING"
cp -R "$BUILD_DIR/$APP_BUNDLE" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

# Create the DMG
hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGING" \
    -ov -format UDZO \
    "$DMG_NAME"

echo ""
echo "Done! Created: $DMG_NAME"
