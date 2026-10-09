#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
usage_test_dir="$(mktemp -d /private/tmp/coucou-usage.XXXXXX)"
trap 'rm -rf "$usage_test_dir"' EXIT
swiftc -module-cache-path "$usage_test_dir/module-cache" \
  NotchBuddy/Sources/App/ClaudePlanGauge.swift \
  NotchBuddy/Sources/App/CoucouUsageSnapshot.swift \
  tests/CoucouUsageSnapshotTests.swift -o "$usage_test_dir/usage-tests"
"$usage_test_dir/usage-tests"
