#!/bin/bash
set -e

# Use Homebrew Swift if available (faster, working toolchain)
if [ -d "/opt/homebrew/opt/swift" ]; then
    export PATH="/opt/homebrew/opt/swift/bin:$PATH"
fi

APP_NAME="SkyPaste"
BUILD_DIR="build"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

# Copy icon
if [ -f "AppIcon.icns" ]; then
    cp AppIcon.icns "${RESOURCES_DIR}/AppIcon.icns"
fi

if [ -f "clip.mp3" ]; then
    cp clip.mp3 "${RESOURCES_DIR}/clip.mp3"
fi

# Create Info.plist
cat << 'EOF' > "${CONTENTS_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleExecutable</key>
    <string>SkyPaste</string>
    <key>CFBundleIdentifier</key>
    <string>com.sky.skypaste</string>
    <key>CFBundleName</key>
    <string>SkyPaste</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSServices</key>
    <array/>
</dict>
</plist>
EOF

# Build with SwiftPM (incremental — only changed files)
swift build -c release 2>&1

# Copy binary to .app bundle
cp .build/release/SkyPaste "${MACOS_DIR}/${APP_NAME}"

# Ad-hoc sign the app — required for UNUserNotificationCenter permission dialog to appear on macOS
codesign --force --deep --sign - "${APP_DIR}"

echo "✅ Build Succeeded! (${APP_DIR})"
