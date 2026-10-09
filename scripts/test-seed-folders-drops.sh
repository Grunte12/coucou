#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir="$(mktemp -d /private/tmp/seed-folders-drops.XXXXXX)"
trap 'rm -rf "$test_dir"' EXIT
swiftc -D COUCOU_HUB -module-cache-path "$test_dir/module-cache" \
  NotchBuddy/Sources/App/SeedFolders.swift \
  NotchBuddy/Sources/App/SeedDropMaterializer.swift \
  tests/SeedFoldersAndDropsTests.swift -o "$test_dir/seed-folders-drops-tests"
"$test_dir/seed-folders-drops-tests"
