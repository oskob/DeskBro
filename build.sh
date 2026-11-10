#!/bin/bash
# Builds DeskBro.app into ./build/DeskBro.app with SwiftPM — no Xcode project needed.
# Requirements: macOS 14+, Xcode or the Command Line Tools (xcode-select --install).
#
# Signing: ad-hoc by default (fine for apps you build yourself). macOS ties Calendar/Reminders
# permission to the signature, so ad-hoc builds re-ask after each rebuild. To avoid that, sign
# with your own certificate:  SIGN_IDENTITY="Apple Development" ./build.sh
set -euo pipefail
cd "$(dirname "$0")"

APP="build/DeskBro.app"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

echo "→ Compiling…"
mkdir -p build
if ! swift build -c release > build/build.log 2>&1; then
  grep -E "error:|warning:" build/build.log | sort -u | head -30
  echo "✗ Build failed (full log: build/build.log)"
  exit 1
fi
BIN="$(swift build -c release --show-bin-path)/DeskBro"

echo "→ Assembling ${APP}…"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "${BIN}" "${APP}/Contents/MacOS/DeskBro"
cp Resources/Info.plist "${APP}/Contents/Info.plist"
iconutil -c icns Resources/AppIcon.iconset -o "${APP}/Contents/Resources/AppIcon.icns"

# If the source was downloaded as a zip in a browser, its files carry a quarantine flag that
# copying would bring into the app. A locally built app shouldn't have it, so clear it.
xattr -cr "${APP}"

echo "→ Signing ($([ "${SIGN_IDENTITY}" = "-" ] && echo ad-hoc || echo "${SIGN_IDENTITY}"))…"
codesign --force --options runtime --entitlements Resources/DeskBro.entitlements \
  --sign "${SIGN_IDENTITY}" "${APP}" 2>&1 | grep -v "replacing existing signature" || true
codesign --verify --strict "${APP}"

echo "✓ Built ${APP}"
