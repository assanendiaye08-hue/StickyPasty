#!/usr/bin/env bash
set -euo pipefail

APP_NAME="StickyPasty"
BUNDLE_ID="com.stickyspasty.app"
VERSION="1.0.0"
BUILD_DIR=".build/release"
APP_BUNDLE="${APP_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS}/MacOS"
RESOURCES_DIR="${CONTENTS}/Resources"

echo "==> Compiling StickyPasty..."
swift build -c release 2>&1

echo "==> Assembling .app bundle..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

# Copy compiled binary
cp "${BUILD_DIR}/${APP_NAME}" "${MACOS_DIR}/${APP_NAME}"

# Write Info.plist
cat > "${CONTENTS}/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>              <string>StickyPasty</string>
    <key>CFBundleIdentifier</key>              <string>com.stickyspasty.app</string>
    <key>CFBundleName</key>                    <string>StickyPasty</string>
    <key>CFBundleDisplayName</key>             <string>StickyPasty</string>
    <key>CFBundleVersion</key>                 <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>      <string>1.0.0</string>
    <key>CFBundlePackageType</key>             <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key>   <string>6.0</string>
    <key>LSMinimumSystemVersion</key>          <string>13.0</string>
    <key>LSUIElement</key>                     <true/>
    <key>NSHighResolutionCapable</key>         <true/>
    <key>NSPrincipalClass</key>                <string>NSApplication</string>
    <key>NSSupportsAutomaticTermination</key>  <false/>
    <key>NSSupportsSuddenTermination</key>     <false/>
    <key>NSHumanReadableCopyright</key>        <string>Copyright 2026 StickyPasty</string>
    <key>NSAppleEventsUsageDescription</key>   <string>StickyPasty uses Apple Events to paste clipboard content.</string>
    <key>NSPhotoLibraryAddUsageDescription</key> <string>StickyPasty needs permission to save clipboard images to Photos.</string>
</dict>
</plist>
PLIST

# PkgInfo marker
printf 'APPL????' > "${CONTENTS}/PkgInfo"

# Copy icon if present
if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
fi

# Ad-hoc code sign (no Developer certificate required)
echo "==> Code signing (ad-hoc)..."
codesign --force --deep --sign - "${APP_BUNDLE}"

echo ""
echo "✓ Built: ${APP_BUNDLE}"
echo "  Binary: $(du -sh ${MACOS_DIR}/${APP_NAME} | cut -f1)"
echo ""
echo "  Run:     open ${APP_BUNDLE}"
echo "  Install: bash install.sh"
