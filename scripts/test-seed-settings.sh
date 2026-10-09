#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir="$(mktemp -d /private/tmp/seed-settings.XXXXXX)"
trap 'rm -rf "$test_dir"' EXIT
swiftc -module-cache-path "$test_dir/module-cache" \
  NotchBuddy/Sources/App/SeedAgentInvite.swift \
  NotchBuddy/Sources/App/SeedActionCatalog.swift \
  tests/SeedSettingsTests.swift -o "$test_dir/seed-settings-tests"
"$test_dir/seed-settings-tests"
