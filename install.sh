#!/usr/bin/env bash
set -euo pipefail

APP_NAME="StickyPasty"
APP_BUNDLE="${APP_NAME}.app"
INSTALL_PATH="/Applications/${APP_BUNDLE}"
BUNDLE_ID="com.stickyspasty.app"
LAUNCH_AGENTS_DIR="${HOME}/Library/LaunchAgents"
PLIST_PATH="${LAUNCH_AGENTS_DIR}/${BUNDLE_ID}.plist"
USER_ID="$(id -u)"

# ── 1. Build ──────────────────────────────────────────────────────────────────
bash "$(dirname "$0")/build.sh"

# ── 2. Install to /Applications ───────────────────────────────────────────────
echo "==> Installing to ${INSTALL_PATH}..."

# Gracefully stop any running instance first
launchctl bootout "gui/${USER_ID}/${BUNDLE_ID}" 2>/dev/null || true

# Kill any running process (belt-and-suspenders)
pkill -x "${APP_NAME}" 2>/dev/null || true
sleep 0.5

if [ -d "${INSTALL_PATH}" ]; then
    rm -rf "${INSTALL_PATH}"
fi
cp -R "${APP_BUNDLE}" "${INSTALL_PATH}"
echo "    Installed to ${INSTALL_PATH}"

# ── 3. Install LaunchAgent for auto-start on login ────────────────────────────
echo "==> Installing LaunchAgent..."
mkdir -p "${LAUNCH_AGENTS_DIR}"

cat > "${PLIST_PATH}" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${BUNDLE_ID}</string>
    <key>Program</key>
    <string>${INSTALL_PATH}/Contents/MacOS/${APP_NAME}</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
    <key>LimitLoadToSessionType</key>
    <string>Aqua</string>
    <key>ProcessType</key>
    <string>Interactive</string>
    <key>AssociatedBundleIdentifiers</key>
    <string>${BUNDLE_ID}</string>
</dict>
</plist>
PLIST

# ── 4. Load immediately (no reboot required) ──────────────────────────────────
echo "==> Loading LaunchAgent and starting app..."
launchctl bootstrap "gui/${USER_ID}" "${PLIST_PATH}"

# Brief pause then open so the user sees it working right now
sleep 1
open "${INSTALL_PATH}"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  StickyPasty installed and running!                  ║"
echo "║                                                      ║"
echo "║  Hotkey:       Option + Cmd + V                      ║"
echo "║  Menu bar:     Click the clipboard icon              ║"
echo "║  Auto-start:   Enabled (runs on every login)         ║"
echo "║  Spotlight:    Search 'StickyPasty' to launch        ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
echo "  To uninstall:"
echo "    launchctl bootout gui/\$(id -u)/${BUNDLE_ID}"
echo "    rm -rf ${INSTALL_PATH}"
echo "    rm ${PLIST_PATH}"
