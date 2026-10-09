#!/bin/bash
# Seed Lab: runs the Seed notch UI in its own window with fixture data,
# drives it from a script and writes snapshots of that window only.
#
#   scripts/seed-lab.sh [--no-build] [--visible] [--release] OUT_DIR (SCRIPT_FILE | -e "cmd; cmd")
#   scripts/seed-lab.sh --rice        interactive Rice Motion Lab v3 window
#
# Separate bundle id (com.grunte.seed.lab): never touches the installed app,
# its preferences, Keychain, the real clipboard or the network. Commands are
# listed in NotchBuddy/Lab/README.md.
set -euo pipefail
cd "$(dirname "$0")/.."

build=1; visible=(); config=Debug; rice=0
while [[ "${1:-}" == --* ]]; do
  case "$1" in
    --no-build) build=0 ;;
    --visible) visible=(--visible) ;;
    --release) config=Release ;;  # optimised build, for CPU numbers
    --rice) rice=1 ;;
    *) echo "unknown flag $1" >&2; exit 2 ;;
  esac
  shift
done
[[ $rice == 1 ]] && set -- "${1:-/tmp}"
out="${1:?usage: seed-lab.sh [--no-build] [--visible] OUT_DIR (SCRIPT | -e \"cmds\")}"; shift
derived="NotchBuddy/build/SeedLab"
app="$derived/Build/Products/$config/SeedLab.app/Contents/MacOS/SeedLab"

if [[ $build == 1 ]]; then
  (cd NotchBuddy && xcodegen -q >/dev/null)
  xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme SeedLab -configuration "$config" \
    -derivedDataPath "$derived" build -quiet 2>&1 | grep -E "error:|warning: unre" || true
  [[ -x "$app" ]] || { echo "build failed" >&2; exit 1; }
fi

if [[ $rice == 1 ]]; then
  exec "$app" --rice
fi
mkdir -p "$out"
if [[ "${1:-}" == "-e" ]]; then
  exec "$app" --out "$out" --run "${2:?-e needs commands}" ${visible[@]+"${visible[@]}"}
else
  exec "$app" --out "$out" --script "${1:?missing script}" ${visible[@]+"${visible[@]}"}
fi
