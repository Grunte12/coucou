#!/bin/sh
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BUILD_DIR="$PROJECT_DIR/build"
MODULE_CACHE="$BUILD_DIR/SwiftTestModuleCache"
TEST_BINARY="$BUILD_DIR/HubIslandContractTests"
SDK_PATH="${SDKROOT:-}"
if [ ! -d "$SDK_PATH" ]; then
  for CANDIDATE in \
    "${DEVELOPER_DIR:-}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk" \
    "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk" \
    "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"; do
    if [ -d "$CANDIDATE" ]; then
      SDK_PATH="$CANDIDATE"
      break
    fi
  done
fi
if [ ! -d "$SDK_PATH" ]; then
  echo "No macOS SDK found; set SDKROOT or DEVELOPER_DIR to an installed Xcode toolchain." >&2
  exit 1
fi

# Keep Hub Island cues opt-in without mutating the user's preferences or playing audio.
if ! grep -Fq '@AppStorage("hubIsland.soundEnabled") private var soundEnabled = false' \
  "$PROJECT_DIR/Sources/HubIsland/HubIslandDashboard.swift" ||
  ! grep -Fq 'guard UserDefaults.standard.bool(forKey: "hubIsland.soundEnabled") else { return }' \
  "$PROJECT_DIR/Sources/HubIsland/HubIslandSound.swift"; then
  echo "Hub Island sound must default to muted and require explicit opt-in." >&2
  exit 1
fi
echo "Hub Island sound default: muted until explicit opt-in."

mkdir -p "$BUILD_DIR" "$MODULE_CACHE"
swiftc \
  -sdk "$SDK_PATH" \
  -target arm64-apple-macosx15.0 \
  -swift-version 6 \
  -strict-concurrency=complete \
  -module-cache-path "$MODULE_CACHE" \
  -o "$TEST_BINARY" \
  -framework Security \
  "$PROJECT_DIR/Sources/HubIsland/HubIslandClient.swift" \
  "$PROJECT_DIR/tests/HubIslandContractTests.swift"
"$TEST_BINARY"

swiftc -sdk "$SDK_PATH" -target arm64-apple-macosx15.0 \
  -swift-version 6 -strict-concurrency=complete \
  -module-cache-path "$MODULE_CACHE" -framework Security \
  "$PROJECT_DIR/Sources/HubIsland/HubIslandClient.swift" \
  "$PROJECT_DIR/Sources/HubIsland/HubIslandModel.swift" \
  "$PROJECT_DIR/tests/HubIslandModelTests.swift" \
  -o "$BUILD_DIR/HubIslandModelTests"
"$BUILD_DIR/HubIslandModelTests"

swiftc -sdk "$SDK_PATH" -target arm64-apple-macosx15.0 \
  -swift-version 6 -strict-concurrency=complete \
  -module-cache-path "$MODULE_CACHE" -framework Security \
  "$PROJECT_DIR/Sources/HubIsland/HubIslandClient.swift" \
  "$PROJECT_DIR/Sources/HubIsland/HubIslandModel.swift" \
  "$PROJECT_DIR/tests/HubIslandOperatorTests.swift" \
  -o "$BUILD_DIR/HubIslandOperatorTests"
"$BUILD_DIR/HubIslandOperatorTests"

swiftc -sdk "$SDK_PATH" -target arm64-apple-macosx15.0 \
  -swift-version 6 -strict-concurrency=complete \
  -module-cache-path "$MODULE_CACHE" \
  "$PROJECT_DIR/Sources/App/IslandScreenGeometry.swift" \
  "$PROJECT_DIR/tests/HubIslandGeometryTests.swift" \
  -o "$BUILD_DIR/HubIslandGeometryTests"
"$BUILD_DIR/HubIslandGeometryTests"

swiftc -sdk "$SDK_PATH" -target arm64-apple-macosx15.0 \
  -swift-version 6 -strict-concurrency=complete \
  -module-cache-path "$MODULE_CACHE" -framework AppKit \
  "$PROJECT_DIR/Sources/HubIsland/HubIslandSound.swift" \
  "$PROJECT_DIR/tests/HubIslandMotionSoundTests.swift" \
  -o "$BUILD_DIR/HubIslandMotionSoundTests"
"$BUILD_DIR/HubIslandMotionSoundTests"
