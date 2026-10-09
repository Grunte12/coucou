#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir="$(mktemp -d /private/tmp/seed-timeline.XXXXXX)"
trap 'rm -rf "$test_dir"' EXIT
swiftc -module-cache-path "$test_dir/module-cache" \
  NotchBuddy/Sources/App/SeedTimelineLayout.swift \
  tests/SeedTimelineLayoutTests.swift -o "$test_dir/seed-timeline-tests"
"$test_dir/seed-timeline-tests"
