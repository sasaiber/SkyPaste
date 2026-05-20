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
FRAMEWORKS_DIR="${CONTENTS_DIR}/Frameworks"

mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}" "${FRAMEWORKS_DIR}"

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
    <string>1.0.1</string>
    <key>CFBundleVersion</key>
    <string>1.0.1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSServices</key>
    <array/>
    <key>SUFeedURL</key>
    <string>https://raw.githubusercontent.com/sasaiber/SkyPaste/main/appcast.xml</string>
    <key>SUPublicEDKey</key>
    <string>t0kuZBdUtqMmLA6aIIjjJaJ9RYpMiA3VLqRFnYP1C04=</string>
</dict>
</plist>
EOF

# Build with SwiftPM (incremental — only changed files)
swift build -c release 2>&1

# Copy binary to .app bundle
cp .build/release/SkyPaste "${MACOS_DIR}/${APP_NAME}"

# Add Frameworks rpath
install_name_tool -add_rpath @executable_path/../Frameworks "${MACOS_DIR}/${APP_NAME}"

# Copy Sparkle.framework
if [ -d ".build/arm64-apple-macosx/release/Sparkle.framework" ]; then
    cp -R ".build/arm64-apple-macosx/release/Sparkle.framework" "${FRAMEWORKS_DIR}/"
fi

# Check if local code signing certificate exists and is valid
CERT_NAME="SkyPaste-Local"
if ! security find-identity -p codesigning -v | grep "${CERT_NAME}" >/dev/null 2>&1; then
    echo "Creating a local self-signed code signing certificate to prevent accessibility permission resets..."
    
    # Delete old certificate if it exists but is invalid
    security delete-certificate -c "${CERT_NAME}" ~/Library/Keychains/login.keychain-db >/dev/null 2>&1
    
    # 1. Generate key and certificate using macOS system openssl (LibreSSL) with Code Signing extensions
    /usr/bin/openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 \
        -keyout /tmp/skypaste.key -out /tmp/skypaste.crt \
        -subj "/CN=${CERT_NAME}" \
        -addext "keyUsage=critical,digitalSignature" \
        -addext "extendedKeyUsage=critical,codeSigning" >/dev/null 2>&1
        
    # 2. Export to PKCS12
    /usr/bin/openssl pkcs12 -export -out /tmp/skypaste.p12 -inkey /tmp/skypaste.key -in /tmp/skypaste.crt -passout pass:skypaste
    
    # 3. Import to login keychain
    security import /tmp/skypaste.p12 -k ~/Library/Keychains/login.keychain-db -P skypaste -T /usr/bin/codesign
    
    # 4. Cleanup temp files
    rm /tmp/skypaste.key /tmp/skypaste.crt /tmp/skypaste.p12
    
    echo "⚠️  Local certificate '${CERT_NAME}' created and imported to your Keychain."
    echo "👉 Please open Keychain Access, find '${CERT_NAME}' in 'login' -> 'My Certificates', double-click it, expand 'Trust', and set 'When using this certificate' to 'Always Trust'."
    echo "This is a one-time step that will stop macOS from resetting Accessibility permissions on every rebuild!"
fi

# Determine signature identity: use local cert if it exists and is trusted, otherwise fallback to ad-hoc (-)
if security find-identity -p codesigning -v | grep "${CERT_NAME}" >/dev/null 2>&1; then
    SIGN_IDENTITY="${CERT_NAME}"
    echo "Signing with local certificate: ${SIGN_IDENTITY}"
else
    SIGN_IDENTITY="-"
    echo "Signing with ad-hoc identity (fallback) — WARNING: Accessibility permissions will reset on every rebuild until you trust '${CERT_NAME}' in Keychain Access!"
fi

codesign --force --deep --sign "${SIGN_IDENTITY}" "${APP_DIR}"

if [ -d "/Applications/SkyPaste.app" ]; then
    echo "Updating /Applications/SkyPaste.app with the new build..."
    rm -rf "/Applications/SkyPaste.app"
    cp -R "${APP_DIR}" "/Applications/SkyPaste.app"
    echo "Registering /Applications/SkyPaste.app with Launch Services (to update Launchpad/Spotlight)..."
    /System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f -R /Applications/SkyPaste.app >/dev/null 2>&1 || true
fi

# Also register the built app in the build directory
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f -R "${APP_DIR}" >/dev/null 2>&1 || true

echo "✅ Build Succeeded! (${APP_DIR})"
