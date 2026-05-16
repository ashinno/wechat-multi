#!/bin/bash
# Install WeChat Multi.app to /Applications and launch it.
set -euo pipefail

APP_NAME="WeChat Multi"
APP_BUNDLE="dist/${APP_NAME}.app"
TARGET="/Applications/${APP_NAME}.app"

cd "$(dirname "$0")"

if [[ ! -d "${APP_BUNDLE}" ]]; then
    echo "==> No build found, running build.sh first…"
    ./build.sh
fi

if [[ -d "${TARGET}" ]]; then
    echo "==> Removing previous install at ${TARGET}"
    rm -rf "${TARGET}"
fi

echo "==> Copying to /Applications…"
cp -R "${APP_BUNDLE}" "${TARGET}"

xattr -dr com.apple.quarantine "${TARGET}" 2>/dev/null || true

echo "==> Launching…"
open "${TARGET}"

echo ""
echo "Installed: ${TARGET}"
echo "Look for the speech-bubble icon in your menu bar (top-right of the screen)."
