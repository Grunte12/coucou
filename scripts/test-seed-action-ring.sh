#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir="$(mktemp -d /private/tmp/seed-action-ring.XXXXXX)"
trap 'rm -rf "$test_dir"' EXIT
swiftc -module-cache-path "$test_dir/module-cache" \
  NotchBuddy/Sources/App/SeedActionCatalog.swift \
  tests/SeedActionRingTests.swift -o "$test_dir/seed-action-ring-tests"
"$test_dir/seed-action-ring-tests"
