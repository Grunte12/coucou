#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir="$(mktemp -d /private/tmp/coucou-rice-motion.XXXXXX)"
trap 'rm -rf "$test_dir"' EXIT
swiftc -D COUCOU_HUB -module-cache-path "$test_dir/module-cache" \
  NotchBuddy/Sources/App/RiceMotion.swift \
  tests/RiceMotionTests.swift -o "$test_dir/rice-motion-tests"
"$test_dir/rice-motion-tests"
