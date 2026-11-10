#!/bin/bash
# Builds DeskBro, installs it to /Applications (or ~/Applications if you're not an admin)
# and launches it.
#
#   ./install.sh           build, install, launch
#   ./install.sh --fresh   same, but reset onboarding + Calendar/Reminders permissions
#                          so you get the first-run experience again
set -euo pipefail
cd "$(dirname "$0")"

FRESH=false
[ "${1:-}" = "--fresh" ] && FRESH=true

# The Command Line Tools provide the Swift compiler. On a fresh Mac, start their installer.
if ! xcrun --find swift >/dev/null 2>&1; then
  echo "DeskBro needs Apple's Command Line Tools to build (free, about 1–2 GB)."
  echo "A dialog will open: click Install, wait for it to finish, then run this again:"
  echo
  echo "    sh install.sh"
  echo
  xcode-select --install >/dev/null 2>&1 || true
  exit 1
fi

# No sudo: install system-wide if we can write there, otherwise just for this user.
if [ -w /Applications ]; then
  DEST="/Applications/DeskBro.app"
  OTHER="${HOME}/Applications/DeskBro.app"
else
  mkdir -p "${HOME}/Applications"
  DEST="${HOME}/Applications/DeskBro.app"
  OTHER=""
fi

bash ./build.sh
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" Resources/Info.plist)"

echo "→ Quitting running DeskBro…"
osascript -e "tell application id \"${BUNDLE_ID}\" to quit" >/dev/null 2>&1 || true
for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x DeskBro >/dev/null || break; sleep 0.3; done
pkill -x DeskBro 2>/dev/null || true

# Keep a single copy (older builds were installed to ~/Applications).
if [ -n "${OTHER}" ]; then rm -rf "${OTHER}"; fi

echo "→ Installing to ${DEST}…"
rm -rf "${DEST}"
cp -R build/DeskBro.app "${DEST}"

if [ "${FRESH}" = true ]; then
  echo "→ Resetting onboarding and permissions…"
  PREFS="${HOME}/Library/Containers/${BUNDLE_ID}/Data/Library/Preferences/${BUNDLE_ID}"
  defaults delete "${PREFS}" hasCompletedOnboarding >/dev/null 2>&1 || true
  tccutil reset Calendar "${BUNDLE_ID}" >/dev/null 2>&1 || true
  tccutil reset Reminders "${BUNDLE_ID}" >/dev/null 2>&1 || true
fi

echo "→ Launching…"
open "${DEST}"
echo "✓ DeskBro is installed and running (look for the icon in the menu bar)."
