#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d "$ROOT/.test-linkhub.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT

swiftc "$ROOT/NotchBuddy/Sources/App/LinkHubHealth.swift" \
    "$ROOT/tests/LinkHubHealthTests.swift" \
    -module-cache-path "$TEST_DIR/module-cache" \
    -o "$TEST_DIR/linkhub-health-tests"
"$TEST_DIR/linkhub-health-tests"
