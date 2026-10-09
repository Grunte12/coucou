#!/usr/bin/env bash
# Build Seed (Debug) and open it straight from the build folder, for hands-on testing.
# Nothing is installed or copied to /Applications. Quit it from the menu bar (Seed → Quit).
#   scripts/run-seed.sh            build, then open
#   scripts/run-seed.sh --no-build open the last build
set -euo pipefail
cd "$(dirname "$0")/.."

# Two notch apps would draw on top of each other.
if pgrep -f "HubIsland.app/Contents/MacOS|Coucou.app/Contents/MacOS" >/dev/null; then
  echo "[seed] HubIsland or Coucou is running. Quit it first (menu bar icon → Quit), then run this again." >&2
  exit 1
fi

if [[ "${1:-}" != "--no-build" ]]; then
  echo "[seed] building Seed (Debug)…"
  (cd NotchBuddy && xcodegen -q && xcodebuild -scheme Seed -configuration Debug -derivedDataPath build/Seed build -quiet)
fi

app="NotchBuddy/build/Seed/Build/Products/Debug/Seed.app"
[[ -d "$app" ]] || { echo "[seed] no build at $app" >&2; exit 1; }

# Restart a running Seed so the new build is the one on screen.
if pgrep -f "Seed.app/Contents/MacOS/Seed" >/dev/null; then
  osascript -e 'tell application id "com.grunte.seed" to quit' >/dev/null 2>&1 || true
  sleep 1
fi
open "$app"
echo "[seed] opened $app"
