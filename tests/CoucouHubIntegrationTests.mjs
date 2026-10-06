import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import assert from 'node:assert/strict';
const source = path => readFileSync(new URL(`../NotchBuddy/${path}`, import.meta.url), 'utf8');

// Build-boundary checks supplement, but do not replace, actual Swift compilation
// and the existing model/API runtime fixture suites.
test('Coucou integration reuses one existing Hub model and is not an inbox consumer', () => {
  const code = source('Sources/App/CoucouHubIntegration.swift');
  assert.equal((code.match(/HubIslandModel\(\)/g) ?? []).length, 1);
  assert.match(code, /static let shared/);
  assert.match(code, /model\.panelHidden\(\)/);
  assert.doesNotMatch(code, /Process\(|check_inbox\(|tincan claim|\/api\/.*claim/);
  assert.match(code, /embedded: true/);
});
test('Coucou host owns metadata polling lifecycle, not a second window', () => {
  const delegate = source('Sources/App/AppDelegate.swift');
  assert.match(delegate, /CoucouHubIntegration\.shared\.start\(\)/);
  assert.match(delegate, /CoucouHubIntegration\.shared\.stop\(\)/);
  assert.doesNotMatch(delegate, /HubIslandWindowController/);
});
test('merged target preserves installed identity and excludes standalone entry point', () => {
  const target = source('project.yml').split('\ntargets:\n')[1].split('\n  NotchBuddy:')[0];
  assert.match(target, /CoucouHub:/);
  assert.match(target, /PRODUCT_BUNDLE_IDENTIFIER: com\.hubisland\.desktop/);
  assert.match(target, /"HubIslandApp\.swift"/);
  assert.match(target, /"HubIslandWindowController\.swift"/);
  assert.match(target, /SWIFT_ACTIVE_COMPILATION_CONDITIONS: COUCOU_HUB/);
});
test('embedded dashboard keeps existing exact-request approval predicate', () => {
  const dashboard = source('Sources/HubIsland/HubIslandDashboard.swift');
  assert.match(dashboard, /var embedded = false/);
  assert.match(dashboard, /model\.canDecideSelectedTincanTask/);
  assert.match(dashboard, /if !embedded/);
  assert.match(source('Sources/App/IslandRootView.swift'), /hubModel\.heldRequestCount/);
});
