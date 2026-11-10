#!/bin/bash
# Re-renders docs/demo.webp (the README animation) and docs/dashboard.png.
# Requires ffmpeg with libwebp (brew install ffmpeg). Not needed to build or use DeskBro.
set -euo pipefail
cd "$(dirname "$0")/../.."

WORK="build/readme-demo"
rm -rf "${WORK}" && mkdir -p "${WORK}/frames" docs

echo "→ Compiling renderer…"
swiftc -O -swift-version 5 -target "$(uname -m)-apple-macos14" \
  Sources/DeskBro/DashboardView.swift Sources/DeskBro/DashboardModel.swift \
  Tools/readme-demo/main.swift -o "${WORK}/readme-demo"

echo "→ Rendering frames…"
# Render in English regardless of this Mac's language.
"${WORK}/readme-demo" "${WORK}/frames" Resources/AppIcon.iconset/icon_256x256.png -AppleLanguages "(en-GB)" -AppleLocale en_GB

echo "→ Encoding docs/demo.webp…"
ffmpeg -loglevel error -y -framerate 20 -i "${WORK}/frames/frame_%04d.png" \
  -vf "scale=1280:-1:flags=lanczos" -c:v libwebp_anim -pix_fmt yuva420p \
  -quality 82 -compression_level 6 -loop 0 docs/demo.webp
cp "${WORK}/dashboard.png" docs/dashboard.png

ls -lh docs/demo.webp docs/dashboard.png
