#!/bin/bash
set -euo pipefail

APP_NAME="AmphetamineXL"
BUNDLE_ID="com.hannojacobs.AmphetamineXL"
DMG_NAME="${APP_NAME}.dmg"
APP_BUNDLE="${APP_NAME}.app"
BUILD_DIR="build-release"

# Find the Release binary from Xcode's DerivedData
BINARY=$(find ~/Library/Developer/Xcode/DerivedData -path "*/Release/${APP_NAME}" -type f 2>/dev/null | head -1)

if [ -z "$BINARY" ]; then
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
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
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
    <string>2.3.1</string>
    <key>CFBundleShortVersionString</key>
    <string>2.3.1</string>
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

# Clean up
rm -rf "$BUILD_DIR"

echo ""
echo "Done! Created: $DMG_NAME"
