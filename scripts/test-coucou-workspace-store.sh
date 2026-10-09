#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-workspace-store.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -swift-version 6 -strict-concurrency=complete \
    -module-cache-path "$TEST_DIR/module-cache" \
    NotchBuddy/Sources/App/CoucouWorkspaceStore.swift \
    tests/CoucouWorkspaceStoreTests.swift \
    -o "$TEST_DIR/coucou-workspace-store-tests"
"$TEST_DIR/coucou-workspace-store-tests"
