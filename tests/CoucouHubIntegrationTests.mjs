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
test('local shelf drop never enters upstream copy/upload flow in the Hub build', () => {
  const integration = source('Sources/App/CoucouHubIntegration.swift');
  assert.match(integration, /let workspace = CoucouWorkspaceStore\(\)/);
  assert.match(integration, /let clipboard = CoucouClipboardAccessService\(\)/);
  assert.match(integration, /clipboard\.disableChangeMonitoring\(\)/);
  const handler = source('Sources/App/FileDropView.swift').split('static func handle(')[1];
  const localBranch = handler.split('#if COUCOU_HUB')[1].split('#else')[0];
  assert.match(localBranch, /stageFiles\(urls\)/);
  assert.match(localBranch, /return/);
  assert.doesNotMatch(localBranch, /copyItem|removeItem|UploadSequenceEngine|promptContext/);
  assert.doesNotMatch(integration, /enableChangeMonitoring\(|captureManually\(|captureIfChanged\(/);
});
test('merged target preserves installed identity and excludes standalone entry point', () => {
  const target = source('project.yml').split('\ntargets:\n')[1].split('\n  NotchBuddy:')[0];
  assert.match(target, /\n  Seed:\n/);
  assert.match(target, /PRODUCT_BUNDLE_IDENTIFIER: com\.grunte\.seed\n/);
  assert.match(target, /"HubIslandApp\.swift"/);
  assert.match(target, /"HubIslandWindowController\.swift"/);
  assert.match(target, /SWIFT_ACTIVE_COMPILATION_CONDITIONS: COUCOU_HUB/);
  // Seed ships its own sounds, never Coucou's.
  assert.match(target, /- path: Resources\/Seed\/sounds\n/);
  assert.doesNotMatch(target, /- path: Resources\/sounds\n/);
});
test('Coucou-native workspace keeps exact-request approval predicate and primitives', () => {
  const pane = source('Sources/App/CoucouAgentPane.swift');
  assert.match(pane, /model\.canDecideSelectedTincanTask/);
  assert.match(pane, /model\.decideSelectedTincanTask/);
  assert.match(pane, /CardBackground\(/);
  assert.match(pane, /SeedAgentRow\(/);
  assert.doesNotMatch(pane, /AgentPill\(/);
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

test('workspace sections keep header anchors, scroll inside the body and never fake usage', () => {
  const pane = source('Sources/App/CoucouAgentPane.swift');
  const header = pane.split('private var header: some View')[1].split('private func tabButton(')[0];
  assert.doesNotMatch(header, /CoucouWorkspaceRail|Section/);
  assert.equal((header.match(/tabButton\(t\)/g) ?? []).length, 1);
  assert.match(pane, /CoucouWorkspaceRail\(selection: section/);
  const usage = source('Sources/App/CoucouUsagePane.swift');
  assert.match(usage, /ScrollView\(\.horizontal/);
  assert.doesNotMatch(usage, /effectivePct/);
  assert.match(usage, /Reset passed/);
  for (const file of ['CoucouShelfPane', 'CoucouClipboardPane', 'CoucouUsagePane']) {
    assert.match(source(`Sources/App/${file}.swift`), /^#if COUCOU_HUB/);
  }
  assert.match(source('Sources/App/CoucouShelfPane.swift'), /ScrollView\(\.vertical/);
  assert.match(source('Sources/App/CoucouClipboardPane.swift'), /ScrollView\(\.vertical/);
});

test('shelf and clipboard UI never touch originals or inject keystrokes', () => {
  const shelf = source('Sources/App/CoucouShelfPane.swift');
  assert.doesNotMatch(shelf, /copyItem|moveItem|removeItem|trashItem|Process\(/);
  assert.match(shelf, /removeFile\(id:/);
  const clip = source('Sources/App/CoucouClipboardPane.swift');
  assert.doesNotMatch(clip, /CGEvent|AXIsProcessTrusted|captureManually\(|Process\(/);
  assert.match(clip, /currentSnapshot\(\)/);
  assert.match(clip, /makeItemProviders\(\)/);
  assert.match(clip, /recopy\(to: \.general\)/);
  assert.match(clip, /guard state\.mode == \.expanded/);
});

test('rice mascot stays inside the Hub build, owns the companion only in the expanded workspace', () => {
  for (const file of ['RiceMotion', 'RiceMascotView', 'CoucouRiceCompanion']) {
    const code = source(`Sources/App/${file}.swift`);
    assert.match(code, /^#if COUCOU_HUB/);
    assert.match(code.trimEnd(), /#endif$/);
    assert.doesNotMatch(code, /Lottie|Rive|NSImage\(named|Image\("|URLSession|approveDecision|decide\(/);
  }
  const motion = source('Sources/App/RiceMotion.swift');
  assert.match(motion, /^import Foundation$/m);
  assert.doesNotMatch(motion, /import (SwiftUI|AppKit)/);
  assert.match(motion, /min\(max\(seconds, 0\), 0\.05\)/);
  assert.match(motion, /1\.0 \/ 120\.0/);
  const view = source('Sources/App/RiceMascotView.swift');
  // No frames at all when paused or Reduce Motion; otherwise an adaptive 60/30/12 fps link.
  assert.match(view, /let live = window != nil && !paused && motion\.needsFrames/);
  assert.match(motion, /case \.full:   return 1\.0 \/ 60\.0/);
  assert.match(view, /RicePainter\.draw\(RiceCanvas\(sink: recorder/);
  const companion = source('Sources/App/CoucouRiceCompanion.swift');
  assert.match(companion, /paused: !reacts \|\| state\.mode == \.hidden/);
  assert.match(companion, /accessibilityLabel\(CoucouBrand.name\)/);
  assert.match(companion, /accessibilityValue\(statusText\)/);
  assert.doesNotMatch(companion, /\.decide|approve\(|sendDecision|submitDecision/);
  const root = source('Sources/App/IslandRootView.swift');
  assert.match(root, /private var hubOwnsCompanion: Bool \{\s+#if COUCOU_HUB\s+return state\.mode == \.expanded && state\.view == \.linkHub\s+#else\s+return false\s+#endif\s+\}/);
  const win = source('Sources/App/IslandWindowController.swift');
  const hit = win.split('private func isBotHit(')[1].split('let panelH')[0];
  // Seed build: no Mochi bot hit at all (no slap, desktop drag or wardrobe).
  assert.match(hit, /#if COUCOU_HUB[\s\S]*?return false\s+#else/);
  assert.match(source('Sources/App/CoucouAgentPane.swift'), /CoucouRiceCompanion\(holder: rice, state: state, section: section,\s+onTap: toggleRing, onFlick: flickRing,\s+reacts: state\.mode == \.expanded && state\.view == \.linkHub\)/);
});

test('agent timeline replaces the Trail list, pans without a system scroll view and never decides', () => {
  const pane = source('Sources/App/CoucouAgentPane.swift');
  assert.match(pane, /case agents, timeline, mcp, review/);
  assert.doesNotMatch(pane, /case \.trail|trailPage/);
  assert.match(pane, /SeedTimelineView\(/);
  const timeline = source('Sources/App/SeedTimelineView.swift');
  // A system scroll view drew a stray bar at the notch edge; panning is ours.
  assert.doesNotMatch(timeline, /ScrollView\(/);
  assert.match(timeline, /addLocalMonitorForEvents\(matching: \.scrollWheel\)/);
  assert.match(timeline, /removeMonitor/);
  // Opening a message hands it to the existing detail view; nothing is decided here.
  assert.doesNotMatch(timeline, /decideSelectedTincanTask|\.decide|approve\(/);
  // Only one Seed view reacts to events, or every reaction would play twice.
  assert.match(source('Sources/App/SeedPlacement.swift'), /reacts: !inWorkspace/);
});

test('Seed opens an Action Ring inside the notch; it never leaves the notch or copies macOS features', () => {
  const pane = source('Sources/App/CoucouAgentPane.swift');
  assert.match(pane, /SeedActionRing\(/);
  assert.doesNotMatch(pane, /SeedShortcutMenu/);
  const ring = source('Sources/App/SeedActionRing.swift') + source('Sources/App/SeedActionCatalog.swift');
  // Seed stays in the notch: no window, panel or desktop drag of its own.
  assert.doesNotMatch(ring, /NSPanel|NSWindow|DesktopMochi/);
  const cases = ring.split('enum SeedAction')[1].split('var title')[0];
  assert.doesNotMatch(cases, /screen|capture|record/i);
  assert.doesNotMatch(ring, /SCScreenshot|CGWindowListCreateImage|screencapture/);
  // Picking an action only navigates or toggles sound; Allow\/Deny stays behind the exact-request detail.
  assert.doesNotMatch(pane.split('private func perform(')[1].split('private func show(')[0], /decide|approve/);
});

test('folders are read-only and drops only write inside Seed\'s own folder', () => {
  const folders = source('Sources/App/SeedFolders.swift') + source('Sources/App/SeedFoldersPane.swift');
  // Browsing never changes the user's files, and a click never launches one.
  assert.doesNotMatch(folders, /removeItem|moveItem|trashItem|copyItem|NSWorkspace\.shared\.open\(/);
  const drops = source('Sources/App/SeedDropMaterializer.swift');
  // The only deletions are week-old files in Seed/Drops.
  const removals = drops.match(/removeItem\(/g) ?? [];
  assert.equal(removals.length, 1);
  assert.match(drops, /appendingPathComponent\("Seed\/Drops"/);
  const drop = source('Sources/App/FileDropView.swift');
  assert.match(drop, /#if COUCOU_HUB\s+\/\/ Seed also takes text, links, images and file promises/);
  assert.match(drop, /#else\s+registerForDraggedTypes\(\[\.fileURL\]\)/);
});

test('Seed opens its own Settings, with its own icons, and writes agent files only after Write', () => {
  const delegate = source('Sources/App/AppDelegate.swift');
  assert.match(delegate, /#if COUCOU_HUB[\s\S]*?SeedSettingsView\(\)[\s\S]*?#else\s+win\.title = "Settings — Coucou"\s+let host = NSHostingView\(rootView: SettingsView\(\)\)/);
  const settings = source('Sources/App/SeedSettingsView.swift');
  // Nothing the user reads says Coucou, Mochi or island.
  const shown = (settings.match(/"(?:[^"\\]|\\.)*"/g) ?? []).join('\n');
  assert.doesNotMatch(shown, /Coucou(?!HubFormat|Noop)|Mochi|island/i);  // code names in interpolations are fine
  // Hook and status line writes happen only in the Write handlers of a shown preview.
  const writes = settings.match(/HookServer\.shared\.write\w+\(\)|uninstallClaudeHooks\(\)/g) ?? [];
  assert.ok(writes.length >= 5);
  for (const fn of ['private func write(', 'private func writeStatusLine(']) assert.ok(settings.includes(fn));
  assert.doesNotMatch(settings.split('private func preview(')[1].split('private func write(')[0], /\.write\w*Hooks\(\)|uninstallClaudeHooks/);
  // Invites go through the local tincan CLI with validated arguments, never a shell.
  const invite = source('Sources/App/SeedAgentInvite.swift');
  assert.doesNotMatch(invite, /\/bin\/(z|ba)?sh|"-c"/);
  assert.match(invite, /guard validName\(name\)/);
  const yml = source('project.yml');
  const seedTarget = yml.split('\ntargets:')[1].split('\n  Seed:\n')[1].split('\n  SeedLab:\n')[0];
  assert.match(seedTarget, /path: Resources\/Seed\/Assets\.xcassets/);
});

test('terminal agents get Seed cards, and approving always takes a click', () => {
  const content = source('Sources/App/IslandViewContent.swift');
  assert.match(content, /#if COUCOU_HUB[\s\S]*?case \.approval: SeedApprovalCard\(state: state\)[\s\S]*?case \.question: SeedQuestionCard\(state: state\)[\s\S]*?case \.finished: SeedFinishedCard\(state: state\)/);
  const cards = source('Sources/App/SeedHookCards.swift');
  const approval = cards.split('struct SeedApprovalCard')[1].split('// MARK: Question')[0];
  assert.doesNotMatch(approval, /keyboardShortcut|defaultAction/);
  assert.match(approval, /HookServer\.shared\.sendApprovalDecision\(answer\)/);
  assert.match(approval, /guard decided == nil/);
  // Coucou's chat, upload and in-notch settings are not reachable from Seed's header.
  const header = source('Sources/App/IslandRootView.swift').split('struct IslandHeader')[1].split('struct TabButton')[0];
  assert.match(header, /#if !COUCOU_HUB\s+TabButton\(icon: "bubble\.left\.fill"/);
  assert.match(header, /#if COUCOU_HUB\s+\/\/ Seed's Settings live in their own window\.\s+NotificationCenter\.default\.post\(name: \.openFullSettings/);
  // Seed's mood also follows terminal agents, and "done" is one shared moment.
  const companion = source('Sources/App/CoucouRiceCompanion.swift');
  assert.match(companion, /state\.pendingApproval != nil \|\| state\.pendingQuestion != nil/);
  assert.match(companion, /if holder\.celebrating \{ return \.done \}/);
});

test('Seed draws outside SwiftUI, one copy at a time, at the rate its motion asks for', () => {
  const view = source('Sources/App/RiceMascotView.swift');
  // A layer-backed view on its own display link; no TimelineView in the notch.
  assert.match(view, /struct RiceMascotView: NSViewRepresentable/);
  assert.doesNotMatch(view, /TimelineView\(/);
  assert.match(view, /displayLink\(target: self, selector: #selector\(tick\(_:\)\)\)/);
  assert.match(view, /let live = window != nil && !paused && motion\.needsFrames/);
  // Sprites composite on the GPU through their own layers.
  assert.match(view, /final class RiceStage/);
  const motion = source('Sources/App/RiceMotion.swift');
  assert.match(motion, /case \.breath: return 1\.0 \/ 12\.0/);
  // Only the Seed on screen draws: hidden copies are paused.
  const companion = source('Sources/App/CoucouRiceCompanion.swift');
  assert.match(companion, /paused: !reacts \|\| state\.mode == \.hidden/);
  // Each IslandView case is one view in Seed: the workspace exists once.
  const content = source('Sources/App/IslandViewContent.swift');
  assert.equal((content.split('#else')[0].match(/CoucouHubPane\(state: state\)/g) ?? []).length, 1);
});
