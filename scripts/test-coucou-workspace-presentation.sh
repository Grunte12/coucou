#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir="$(mktemp -d /private/tmp/coucou-presentation.XXXXXX)"
trap 'rm -rf "$test_dir"' EXIT
swiftc -D COUCOU_HUB -module-cache-path "$test_dir/module-cache" \
  NotchBuddy/Sources/App/ClaudePlanGauge.swift \
  NotchBuddy/Sources/App/CoucouUsageSnapshot.swift \
  NotchBuddy/Sources/App/CoucouWorkspacePresentation.swift \
  tests/CoucouWorkspacePresentationTests.swift -o "$test_dir/presentation-tests"
"$test_dir/presentation-tests"
