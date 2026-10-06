#!/bin/sh
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BUILD_DIR="$PROJECT_DIR/build"
APP_PATH="$BUILD_DIR/HubIsland.app"
CONTENTS="$APP_PATH/Contents"
MACOS="$CONTENTS/MacOS"
MODULE_CACHE="$BUILD_DIR/SwiftModuleCache"
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

mkdir -p "$MACOS" "$CONTENTS/Resources" "$MODULE_CACHE"
cp "$PROJECT_DIR/Resources/HubIsland-Info.plist" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable HubIsland" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDevelopmentRegion en" "$CONTENTS/Info.plist"

swiftc \
  -sdk "$SDK_PATH" \
  -target arm64-apple-macosx15.0 \
  -swift-version 6 \
  -strict-concurrency=complete \
  -module-cache-path "$MODULE_CACHE" \
  -parse-as-library \
  -o "$MACOS/HubIsland" \
  -framework AppKit \
  -framework SwiftUI \
  -framework Security \
  "$PROJECT_DIR/Sources/CoucouKit/IslandScreenGeometry.swift" \
  "$PROJECT_DIR/Sources/HubIsland/HubIslandClient.swift" \
  "$PROJECT_DIR/Sources/HubIsland/HubIslandModel.swift" \
  "$PROJECT_DIR/Sources/HubIsland/HubIslandApp.swift" \
  "$PROJECT_DIR/Sources/HubIsland/HubIslandInstaller.swift" \
  "$PROJECT_DIR/Sources/HubIsland/HubIslandSound.swift" \
  "$PROJECT_DIR/Sources/HubIsland/HubIslandShape.swift" \
  "$PROJECT_DIR/Sources/HubIsland/HubIslandDashboard.swift" \
  "$PROJECT_DIR/Sources/HubIsland/HubIslandWindowController.swift"

echo "Built $APP_PATH"
