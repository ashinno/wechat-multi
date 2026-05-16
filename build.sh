#!/bin/bash
# Build WeChat Multi.app from the Swift package.
set -euo pipefail

APP_NAME="WeChat Multi"
BUILD_DIR=".build/release"
DIST_DIR="dist"
APP_BUNDLE="${DIST_DIR}/${APP_NAME}.app"

cd "$(dirname "$0")"

echo "==> Building release binary…"
swift build -c release

if [[ ! -f "${BUILD_DIR}/WeChatMulti" ]]; then
    echo "Error: build did not produce ${BUILD_DIR}/WeChatMulti" >&2
    exit 1
fi

echo "==> Assembling app bundle…"
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${BUILD_DIR}/WeChatMulti" "${APP_BUNDLE}/Contents/MacOS/WeChatMulti"
cp "Resources/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"

# App icon. Regenerate the .icns if the source script is newer than the bundled
# version (no-op on most builds). Then ship it into the .app's Resources.
if [[ -f "Resources/AppIcon.icns" && \
      "tools/make_icon.swift" -nt "Resources/AppIcon.icns" ]]; then
    echo "==> Icon script newer than .icns — regenerating…"
    ./tools/make_icns.sh
fi
if [[ -f "Resources/AppIcon.icns" ]]; then
    cp "Resources/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
fi

# Make sure the binary is executable
chmod +x "${APP_BUNDLE}/Contents/MacOS/WeChatMulti"

echo "==> Ad-hoc signing…"
codesign --force --deep --sign - "${APP_BUNDLE}" 2>/dev/null || true

# Remove quarantine attribute so Gatekeeper doesn't block local launches
xattr -dr com.apple.quarantine "${APP_BUNDLE}" 2>/dev/null || true

echo ""
echo "Built: ${APP_BUNDLE}"
echo "Run:    open \"${APP_BUNDLE}\""
echo "Install: ./install.sh"
