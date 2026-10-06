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
  assert.match(code, /CoucouAgentWorkspace\(/);
  assert.doesNotMatch(code, /HubIslandDashboardView\(/);
});
test('Coucou host owns metadata polling lifecycle, not a second window', () => {
  const delegate = source('Sources/App/AppDelegate.swift');
  assert.match(delegate, /CoucouHubIntegration\.shared\.start\(\)/);
  assert.match(delegate, /CoucouHubIntegration\.shared\.stop\(\)/);
  assert.doesNotMatch(delegate, /HubIslandWindowController/);
  assert.match(delegate, /islandController\?\.collapse\(\)/);
  assert.match(source('Sources/App/CoucouHubIntegration.swift'), /post\(name: \.coucouHubCollapse/);
});
test('merged target preserves installed identity and excludes standalone entry point', () => {
  const target = source('project.yml').split('\ntargets:\n')[1].split('\n  NotchBuddy:')[0];
  assert.match(target, /CoucouHub:/);
  assert.match(target, /PRODUCT_BUNDLE_IDENTIFIER: com\.hubisland\.desktop/);
  assert.match(target, /"HubIslandApp\.swift"/);
  assert.match(target, /"HubIslandWindowController\.swift"/);
  assert.match(target, /SWIFT_ACTIVE_COMPILATION_CONDITIONS: COUCOU_HUB/);
});
test('Coucou-native workspace keeps exact-request approval predicate and primitives', () => {
  const pane = source('Sources/App/CoucouAgentPane.swift');
  assert.match(pane, /model\.canDecideSelectedTincanTask/);
  assert.match(pane, /model\.decideSelectedTincanTask/);
  assert.match(pane, /CardBackground\(/);
  assert.match(pane, /AgentPill\(/);
  const row = pane.split('private func transferRow(')[1].split('// MARK: Transfer detail')[0];
  assert.doesNotMatch(row, /entry\.(title|body)/);
  assert.doesNotMatch(pane, /Process\(|check_inbox\(/);
  assert.match(pane, /ForEach\(detail\.steps\)/);
  assert.doesNotMatch(pane, /detail\.steps\.prefix/);
  assert.match(source('Sources/App/IslandRootView.swift'), /hubModel\.heldRequestCount/);
  assert.match(source('Sources/App/IslandWindowController.swift'), /#if COUCOU_HUB\s+return \.linkHub/);
});

test('agent selection cannot resize the host or overlap labels with Mochi', () => {
  const pane = source('Sources/App/CoucouAgentPane.swift');
  const detail = pane.split('private func agentDetail(')[1].split('private func factRow(')[0];
  assert.match(pane, /height: max\(0, bounds\.size\.height - 24\)/);
  assert.match(pane, /height: bounds\.size\.height, alignment: \.topLeading/);
  assert.match(detail, /GeometryReader/);
  assert.match(detail, /ScrollView\(\.vertical\)/);
  assert.match(detail, /fixedSize\(horizontal: false, vertical: true\)/);
  const pill = source('Sources/App/IslandViewContent.swift').split('struct AgentPill: View')[1].split('struct PillBadgeView')[0];
  const integrated = pill.split('// Reserve a real icon column:')[1].split('#else')[0];
  assert.match(integrated, /HStack\(spacing: 6\)/);
  assert.match(integrated, /frame\(width: 30, height: 22/);
  assert.match(integrated, /Text\(displayName\)/);
  assert.match(integrated, /alignment: \.leading/);
});
