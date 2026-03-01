#!/bin/bash

APP_NAME="SkyPaste"
BUILD_DIR="build"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
PLIST_PATH="${CONTENTS_DIR}/Info.plist"

# Clean
rm -rf "${BUILD_DIR}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

if [ -f "AppIcon.icns" ]; then
    cp AppIcon.icns "${RESOURCES_DIR}/AppIcon.icns"
fi

# Create Info.plist
cat <<EOF > "${PLIST_PATH}"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.sky.skypaste</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/> <!-- Runs as menu bar/utility app (no Dock icon initially) -->
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSServices</key>
    <array/>
</dict>
</plist>
EOF

# Compile
echo "Compiling..."

# Search for all Swift files
SWIFT_FILES=$(find Sources -name "*.swift")

if [ -z "$SWIFT_FILES" ]; then
    echo "No Swift files found in Sources/"
    exit 1
fi

# Compile using swiftc
swiftc $SWIFT_FILES -o "${MACOS_DIR}/${APP_NAME}" \
    -target arm64-apple-macosx14.0 \
    -O -whole-module-optimization \
    -framework SwiftUI \
    -framework AppKit \
    -framework Combine \
    -framework UniformTypeIdentifiers

if [ $? -eq 0 ]; then
    echo "Build Succeeded!"
    echo "App Location: ${APP_DIR}"
else
    echo "Build Failed."
    exit 1
fi
