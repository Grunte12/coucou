# Code Coach — Notch UI handoff receipt

- Session: the persistent Code Coach — Notch UI Claude Code session (Opus 5.5).
  Conversation UUID: `ebefd411-714f-4d2c-b9c9-3dd291a52632` (taken from this
  session's scratchpad path; the runtime does not expose the ID any other way).
- Request received from peer session `linkhub-island-79` on 2026-10-06.
- Handoff read: yes — `CLAUDE_NOTCH_FEATURE_HANDOFF.md` and `CLAUDE.md`.
- Scope: **accepted** — UI and mascot only (clipboard panel, file shelf, AI usage
  cards, panel scrolling and anchors, rice mascot motion).
- Out of scope, not touched: routing, credentials/Keychain, signing and bundle
  identity (`com.hubisland.desktop`), hooks, permissions, approval authority,
  backend policy, media generation, push/release, global install.
- Session permissions: plan mode exited and edits allowed. Nothing held.

This receipt shows the handoff was delivered. It does not show the UI is finished;
results are recorded in the "Implementation log" below as work proceeds.

## Implementation log

- 2026-10-06: the owner asked for a detailed implementation plan first
  (`plans/003-notch-ui-workspace.md`).
- 2026-10-07: owner approved implementation and made two changes to the plan.
  1. The rice mascot is designed separately from the notch UI. Its motion list is
     `brand/rice/MOTION_LIST.md`, **awaiting owner review**. No mascot code yet;
     Mochi stays until it is approved.
  2. Clipboard points at the Mac's clipboard (current pasteboard item, read only
     while the pane is open and never stored). Opt-in history stays off by default.
     macOS exposes no API for its own ⌘Space history, so that cannot be shown.
- Notch UI implemented (CoucouHub target only): section rail in the left gutter
  (Agents / Shelf / Clipboard / Usage), `CoucouShelfPane`, `CoucouClipboardPane`,
  `CoucouUsagePane`, `CoucouWorkspacePresentation`; Mochi moved to a fixed height
  (`IslandConst.hubBotY`) to make room; dragging files into the notch opens Shelf.
- One additive change to Codex's backend: `CoucouClipboardAccessService` gained
  `currentChangeCount` and `currentSnapshot()` (read-only, retains nothing, same
  allow-list and sensitive-marker rejection). Please confirm with Codex.
- Verified: `CoucouHub` and `NotchBuddy` Debug builds succeed; workspace-store,
  usage and new presentation Swift tests pass; Node integration tests (8) and
  `brand/rice/motion.test.mjs` pass.
- **Not yet verified (live gates):** real drags to Finder/TextEdit/VS Code/Claude,
  Copy fallback, VoiceOver, Reduce Motion, native panel captures, whether macOS
  shows a pasteboard-access prompt on this OS version. A Debug run shares the
  installed app's bundle id, so it needs the owner's go-ahead. Nothing committed,
  pushed or installed.
- 2026-10-07 (later): owner rejected the protruding-eye design and asked for a full
  redesign. Mascot v2 (eyes inside the body, white-to-light-yellow grain, gold rim,
  luminous yellow glow) is in `brand/rice/motion-lab.html` (interactive, for owner
  choices) and `brand/rice/rice-v2.svg`. Still no Swift mascot code: waiting for the
  owner's choices from the lab. Owner also allowed a temporary Debug run; none done yet.
- 2026-10-07 (later still): owner asked for premium, Apple-grade, non-game motion (no star
  bursts, nothing pointed). An Opus subagent rebuilt `brand/rice/motion-lab.html` as v4
  (own light language: grain-shaped ripple, rim light, aura breath, few round motes, light
  pool; every intent distinct by posture; Thai wai and bilingual captions). Draft kept at
  `brand/rice/motion-lab.v3-draft.html`; `rice-v2.svg` synced. Checked in a browser by the
  subagent and spot-checked by me (no console errors, 7 states distinct at 52 px). Not
  verified: long-session frame pacing/CPU, real Finder drag, real notch, Safari. No Swift
  mascot code yet; waiting for the owner's choices.
- 2026-10-07 (latest): owner stopped the Opus subagents; I continued myself. The rice mascot
  is ported (`RiceMotion.swift`, `RiceMascotView.swift`, `CoucouRiceCompanion.swift`), wired into
  the workspace gutter, Mochi hidden only while expanded on `.linkHub`. `CoucouHub` and
  `NotchBuddy` Debug builds succeed; all Swift test scripts (incl. new rice motion) and 15 Node
  checks pass. Small additive change in Codex's `CoucouHubIntegration.swift`: posts
  `.coucouShelfRejected` when the shelf rejects a drop.
- Live run: launched the Debug HubIsland.app (not installed, then killed). `screencapture`
  failed ("could not create image from rect": Screen Recording not granted to this process),
  so there are NO live screenshots yet and the mascot's on-screen layout is UNVERIFIED.
- CPU while the island was hidden measured 10-15% in this Debug build. A 4 s `sample` shows the
  hot frames are Mochi's `MochiOutfitDrawing` (existing code), no rice frames. Not yet compared
  with a build from `main` or a Release build, so whether this predates our changes is unknown.
- 2026-10-07 (performance pass): CORRECTION to the earlier CPU note. The "10-15%" came from
  `ps -o %cpu`, a since-launch average that includes the startup burst. Instantaneous `top`
  numbers for the Debug app with the island hidden were 0.6-1.6%. Mascot optimizations (kept
  visually identical, compared before/after snapshots): the three always-on blur layers and the
  approval ring are blurred once into cached bitmaps; the working-arc and rim-pass glows use
  layered strokes instead of a live blur; frame rate is 60 fps while anything moves and 24 fps
  only for the idle breath/aura. Standalone bench (rice mascot alone, optimized build, scratch
  only): idle 6.3% -> about 2-4% of one core; working 5.3% -> 4.6%; pointer-follow unchanged
  (stays at 60 fps by design). Owner decision: smoothness and charm outrank a few percent CPU.
  Competitor CPU not measured (apps not installed); only anecdotal public reports found.
- 2026-10-07 (Seed Lab): owner asked for an agent-run test setup so nobody has to hold the
  notch open, and a working name "Seed". Added:
  - `SeedLab` XcodeGen target (`NotchBuddy/Lab/`, own bundle id `com.hubisland.seedlab`, flags
    `COUCOU_HUB COUCOU_LAB`, never installed) and `scripts/seed-lab.sh`. It runs the real
    `IslandRootView` in a plain window behind other windows, with a fixture Hub API, a private
    pasteboard, no Keychain and no network; drives it by script (in-process clicks, drops,
    copies, usage states) and writes snapshots of its own window plus CPU numbers.
    `NotchBuddy/Lab/walkthrough.lab` covers every section and state (28 outputs, 0 failures).
    See `NotchBuddy/Lab/README.md`.
  - Lab-only hooks, all under `#if COUCOU_LAB`: fixture API/pasteboard in Codex's
    `CoucouHubIntegration.swift` (Codex to confirm), the Copy target in the clipboard pane, and a
    pointer path into the existing gaze handler (synthetic moves do not reach hover tracking).
  - `CoucouBrand.name = "Seed"` for the notch UI text I own (clipboard/usage copy, mascot
    VoiceOver label). Bundle display name ("Hub Notch") and upstream strings are unchanged.
  Found and fixed through the lab:
  - Mochi kept drawing at opacity 0 behind the rice in the expanded workspace. `BotCanvasView`
    now pauses its timeline there (`COUCOU_HUB` only, not desktop Mochi).
  - Usage detail showed old "80% used · 20% left" after a reset passed; now shows only "Reset
    passed · waiting for new data" (`CoucouWorkspaceFormat.windowDetail`, tested).
  - Clipboard history repeated the item already shown as "On the clipboard now"; deduped.
  - Shelf/clipboard/usage lists were cut hard at the footer; added a bottom fade.
  CPU in the lab (Release, lab window always on screen, so compare states only): compact ~10%
  (upstream Mochi), Usage ~16-21%, Agents ~27-37% (Agents pills dominate). Freezing the rice
  changes Usage by only ~1-5 points. Hosting the rice in its own NSHostingView made it worse
  and was reverted.
  Still unverified: real notch placement, real hover tracking, drags into other apps,
  VoiceOver, macOS prompts. Owner to review: the resting pose (lies on its side, closed eyes
  read as vertical marks at 52 pt).
  Builds: SeedLab, CoucouHub and NotchBuddy Debug succeed. Tests: 9/9 Node, all Swift scripts pass.
- 2026-10-07 (design pass + rice v3): owner asked for balanced spacing, a minimal and clean UI
  (details on demand), a CPU verdict, and allowed a full redesign of the rice (keep the oval
  grain; white body, golden rim and aura). Done, all checked through Seed Lab:
  - Rice v3 (`RiceMascotView.swift`, `RiceMotion.swift`): pure white body with a faint pearl shade,
    thinner crisp gold rim, deeper gold glow, stronger aura. Resting no longer lies on its side:
    it dozes upright (-7 deg lean, slow nod every 6-9 s, horizontal closed eyes, z). Working arc
    now drawn above the aura (it was washed out). Ripples are soft additive light bands (thin pale
    lines read grey on the dark notch). Eyes close by height instead of a grey cross-fade.
    `brand/rice/motion-lab.html` still shows v2; the Swift is the source of truth for v3.
    v2 copies kept in the scratchpad only.
  - Spacing: 4/8/12/16 scale (`CoucouWorkspaceStyle.gap/sectionGap`), 12 pt under every header.
  - Agents: one summary line ("hook · active 1 sec ago · 2 queued"); Wake/Last active/Queue/Kind
    and the presence note behind a Details toggle; disabled Wake button removed; pills in one
    full-width column so names no longer truncate.
  - Shelf: count as subtitle, row actions appear on hover, size only (path and time in the
    tooltip), disabled "Send to agent" footer removed.
  - Clipboard: no subtitle; "Now" / "Earlier"; the three notes moved behind an info toggle.
  - Usage: info toggle replaces the subtitle and trust line; cards show big percentages, compact
    "No data" cards for unwired providers; details open only when a card is tapped.
  CPU after the pass (Release lab, compare states only): compact ~9%, Usage ~16%, Agents ~25%,
  working ~18%. Unchanged or slightly lower.
  Known leftover: faint vertical end marks on agent pills come from the shared `AgentPill` view
  (not changed). Builds: CoucouHub and NotchBuddy Debug succeed. Tests: 9/9 Node, Swift scripts pass.
- 2026-10-07 (owner direction: our own product, no Coucou look): Rice Motion Lab v3 added as a
  real Swift window (`NotchBuddy/Lab/RiceMotionLab.swift`, `scripts/seed-lab.sh --rice`); the
  HTML lab is marked v2 in `brand/rice/MOTION_LIST.md`. Agent list no longer uses the upstream
  Mochi `AgentPill`: new `SeedAgentRow.swift` (agent-coloured grain, gold hover wash, gold
  selection rim drawn inside the row; the faint end marks are gone). Node test updated to pin
  `SeedAgentRow(` and forbid `AgentPill(` in the pane. Builds and tests pass.
  Owner direction recorded, not built yet (awaiting choices): replace Mochi everywhere with the
  rice; rename away from CoucouHub/NotchBuddy; own sounds (ElevenLabs proposed, needs a key);
  own hover language everywhere; drag-and-drop-first features; agent-to-agent timeline with
  clickable edges.
- 2026-10-07 (owner decisions applied): app is **Seed**.
  - Rename:
    - The `CoucouHub` target/scheme is now `Seed`. PRODUCT_NAME and CFBundleName are Seed, and the bundle id is **`com.grunte.seed`**.
    - `Resources/CoucouHub-Info.plist` was git-moved to `Seed-Info.plist`.
    - The lab bundle id is `com.grunte.seed.lab`.
    - The menu bar reads "Open Seed".
    - The Node test now pins the new identity.
    - Not changed: the `COUCOU_HUB` compile flag and the Keychain service string `com.hubisland.desktop` in Codex's `HubIslandClient.swift`, so the stored Hub credential keeps its name.
    - A new bundle id means macOS permissions and preferences start fresh, and the user may see one Keychain prompt or need to re-pair.
    - `scripts/sign-local-app.sh` still pins `HubIsland.app` and `com.hubisland.desktop`; Codex or the owner should update it before installing Seed.
  - Seed replaces Mochi everywhere in this build:
    - `SeedPlacement.swift` draws Seed at Mochi's spot in the closed strip and in every expanded view. It shares one motion with the workspace (`RiceMotionHolder.shared`).
    - The per-agent mini Mochi grid is hidden.
    - The Mochi greeting is replaced by Seed's wai (`.seedGreet`, posting `greetComplete` after 2.2 s).
    - Bot slap, drag-to-desktop, wardrobe and the desktop fly-back are off (`isBotHit` returns false under COUCOU_HUB).
  - Tapping Seed opens its shortcuts (`SeedShortcutMenu.swift`): Agents, Review (when held), Shelf, Clipboard, Usage, Settings.
  - Sounds: ElevenLabs flow "Seed UI sounds v1" (BdnNp7SXmT3v5hNm0Pus). There are 16 sounds matching the names the app plays, 2 variations each, about 218 credits. They are not downloaded or installed yet; that is waiting for the owner's OK.
  - Plans: `plans/004-agent-timeline.md` recommends horizontal swimlanes with clickable edges. `plans/005-agent-first-seed.md` proposes a local MCP server, `seed.json` and a skill so users' own agents customize Seed (needs Codex).
  - Builds: Seed, NotchBuddy and SeedLab Debug all succeed. Tests: 9/9 Node, Swift scripts pass.

## 2026-10-07 · Seed sounds installed (owner approved the download)
- 31 of 32 ElevenLabs generations downloaded (one tick-b signed link had expired; tick-a used).
- 24 WAVs written to `NotchBuddy/Resources/Seed/sounds/`, same names as Coucou's, level-matched per name (see `brand/sounds/README.md`).
- `project.yml`: the Seed and SeedLab targets now bundle `Resources/Seed/sounds`; the NotchBuddy and App Store targets are unchanged.
- Test pin added: the Seed target uses Seed's sounds, never `Resources/sounds`.
- Results: xcodegen ok; Seed and SeedLab Debug builds succeed; node 9/9; afinfo decodes every file.
- Not verified: listening by ear in the real notch. Silent in Seed: slap, annoyed, dizzy, gulp, yawn (Mochi-only).

## 2026-10-07 · Agent timeline (plan 004) built; Trail tab replaced
- New files:
  - `SeedTimelineLayout.swift`: pure layout and hit-testing, tested by `scripts/test-seed-timeline.sh`.
  - `SeedTimelineView.swift`: the Canvas view.
- How it works:
  - Swimlanes, newest at the right next to "now", with steps by message order rather than clock time.
  - Curve colour shows state: held amber with a 15 fps breathing dot, open cyan, answered green with a return hook, failed red dashed.
  - Hover brightens a curve. A click dims the rest and slides up a card. The card's Open/Review button hands off to the existing transfer detail; Allow/Deny stay there and are unchanged.
  - Lane labels focus one agent. The agent detail's "Timeline" button does the same.
  - Panning is our own (trackpad and wheel through a local monitor, click-drag, and a "Now" pill). The system ScrollView was dropped because a stray scroll bar appeared at the window edge.
  - Reading history keeps its place when new messages arrive.
- Seed reacts: a new message or a selected one posts `.seedGlance` and Seed looks toward the timeline.
- Fixed a double reaction:
  - The strip Seed (SeedPlacement) and the workspace Seed both handled every event on the shared motion.
  - Now only one view reacts at a time (`reacts:`).
  - The quiet copy still tracks the held baseline, so nothing replays when control passes back.
- Lab:
  - New fixture `timeline`: 3 agents, 10 messages.
  - New `scrollers` command, which lists every scroll view and scroller.
  - `scroll` also posts `.seedLabScroll`.
  - Walkthrough steps 30–33 added.
- Known lab-only artifact: after a synthetic horizontal scroll, a faint bar appears at the window bottom. The timeline has no scroll view, so the bar comes from the lab handing raw events to the view under the point; the monitor consumes real events first. **To check in the real notch.**
- Results:
  - Seed, NotchBuddy and SeedLab Debug builds succeed.
  - Node 10/10.
  - Swift tests: rice motion, presentation and timeline pass.

## 2026-10-07 · Seed's Action Ring replaces the shortcut menu (owner: no dragging Seed, stays in the notch)
- Owner's direction:
  - Seed is not dragged and never leaves the notch (CPU, and no trouble with other apps).
  - No copies of Apple features such as screenshots.
  - Tapping Seed opens an Actions Ring like the MX Master's, with user-configurable actions.
  - Files still go to the shelf by dropping them on the notch directly.
- Files:
  - `SeedActionCatalog.swift`: pure, tested by `scripts/test-seed-action-ring.sh`.
    - 11 actions, all Seed's own features.
    - `SeedRingStore`: max 6, UserDefaults `seed.ring.slots`, forgiving decode, toggle and reset.
    - `SeedRingGeometry`: a fan from -12° to 102° at radius 104 around Seed's centre (44,42), so it never crosses the notch edge; directional slot pick with a 16 pt dead zone and 30° of leeway.
  - `SeedActionRing.swift`: the ring view, badges for held requests and shelf count, the highlighted slot's label, the Customize chip, and the `SeedRingEditor`.
  - `SeedShortcutMenu.swift`: deleted.
- Interaction:
  - Tap Seed: the ring blooms and the rest of the pane dims. Point and click, or click Seed or outside to close; Esc closes the ring first.
  - Press Seed and flick toward a slot: the ring opens on the way and the release picks.
  - Customize opens the editor in place of the pane body.
- Seed reacts:
  - `ringOpen` (lift and rim pass), `lookAt` toward the pointed slot, `ringPick` (nod and gold ripple), `ringClose`.
  - New `notice(dx:dy:)` via `SeedReaction.notice` for header tabs, agent rows, shelf remove/clear and usage cards.
- Lab: a `flick` command and walkthrough steps 40–43. CPU with the ring open is about 9.5% (Debug lab).
- Results:
  - Seed, NotchBuddy and SeedLab Debug builds succeed.
  - Node 11/11.
  - Swift: action ring, timeline, rice motion and presentation all pass.
- Not verified live: real pointer hover over the ring, a real trackpad flick, VoiceOver on the ring.

## 2026-10-07 · Drops from agent apps, pinned folders, agent-editable settings, test kit
- Drops that are not files (`SeedDropMaterializer.swift`, Seed build only; the Coucou build still accepts file URLs only).
  - What it accepts and writes:
    - text → snippet `.txt`, named after its first line
    - http(s) link → `.webloc`
    - image → `.png`
    - file promises → received into the same folder
  - Folder: `~/Library/Application Support/Seed/Drops/`. Week-old files there are cleared, and nothing outside it is written.
  - The pasteboard is read during `performDragOperation`; only promise delivery is awaited, with a 15 s cap.
  - Results go through the existing `stageFiles`, so the shelf's rules and rejection still apply.
- Pinned folders (`SeedFolders.swift`, `SeedFoldersPane.swift`).
  - New rail section `folders`, added last so earlier rail coordinates are unchanged.
  - Up to 8 pins, stored in UserDefaults `seed.folders.pins`. Add uses NSOpenPanel above the notch level.
  - While Folders is open, a dropped folder is pinned and dropped files still go to the shelf; the drag-enter no longer forces Shelf in that case.
  - Listing is newest first, hides hidden files, treats packages as one item, caps at 120, and runs off the main thread.
  - Rows drag out to agent apps, with hover buttons for "add to shelf" and "reveal". Never launches or changes files; this is pinned by a test.
  - `folders` is also an Action Ring action.
- Agent-first v0, with no backend:
  - The user's agent can set `seed.ring.slots` and `seed.folders.pins` with `defaults write com.grunte.seed …`.
  - Seed re-reads them when the ring opens or Folders appears.
  - Guide: `docs/seed/SEED_SKILL.md`.
  - Verified in the lab through its own domain: a bogus id and a duplicate were dropped, and the lab key was removed afterwards.
- Fix: the ring's Customize chip moved to radius + 90 so it no longer covers the middle slot's label when the slot count is odd.
- Lab: new `dropin text|link|image` command (writes only under the lab output folder), `pin` command, and walkthrough steps 50–53.
- Tests: new `scripts/test-seed-folders-drops.sh`. Node 12/12.
- Owner test kit:
  - `scripts/run-seed.sh` builds Seed Debug and opens it from the build folder. It does not install, and it refuses to run while HubIsland or Coucou is running.
  - `docs/seed/TEST_CHECKLIST.md` (Thai).
- Still open (needs the owner or Codex): the plan 005 MCP server, the Tincan "Proof" button design, the signing script for Seed.app, and the Keychain service name.

## 2026-10-07 · Seed Settings and agent connections (Claude, UI)
- New `SeedSettingsView.swift` (COUCOU_HUB): General, Agents, Action Ring, Folders, About. AppDelegate opens it in the Seed build only; Coucou's `SettingsView` is untouched.
- Agents page: Tincan roster through LinkHub (read-only, existing `HubIslandModel`), "Add an agent" invite via local `tincan invite --socket <admin.sock>` (`SeedAgentInvite.swift`), terminal hooks for Claude Code / Codex / Gemini CLI / Antigravity and the Claude status line, all through existing `HookServer` preview → Write.
- Seed asset catalog `NotchBuddy/Resources/Seed/Assets.xcassets` (rice app icon and template menu bar icon; sources in `brand/rice/icon-*.html`). Seed and SeedLab targets use it.
- `SeedRingStore.move(_:by:)`; agent pane "Not set up" notice links to Agent settings; lab command `settings <page> [height]`.
- Tests: `scripts/test-seed-settings.sh`; node pins 13/13. Backend note for Codex: Seed and Coucou share `~/Library/Application Support/NotchBuddy/nb.sock` and nb-hook, so only one may run at a time (run-seed.sh already enforces this).

## 2026-10-07 · UI, motion and Seed: design phase closed (Claude, UI)
- Seed cards for terminal-agent hooks: `SeedHookCards.swift` (approval, question, finished, busy). `IslandViewContent` routes to them under COUCOU_HUB; every other view in the Seed build is the workspace. Allow has no keyboard shortcut.
- Header in the Seed build: house, gear (opens the Seed Settings window), sound. Coucou's chat and upload tabs are hidden.
- Shared tokens and button: `SeedDesign.swift` (`SeedInk`, `SeedButtonStyle`); Settings uses them.
- Mascot: mood also follows hooks (pending approval/question → approval, working hook tasks → working); a shared "done" moment (`RiceMotionHolder.celebrate`) after a held request is decided, a hook approval is answered, or a session finishes; `RiceMotion.opened()` and `folded()` on notch open/fold. Countdown line is gold.
- Lab: `alert approval [pillId] | question | finished | clear`.
- Tests: node pins 14/14; all Seed and related Swift suites pass; Seed, SeedLab and Coucou build.
- **Handoff to Codex (backend), from here:** see `docs/seed/SETUP_LATER.md` → "งานหลังบ้านที่ส่งต่อให้ Codex". UI work stops here until the owner's review.

## 2026-10-08 · Seed CPU optimisation (Claude, UI)
Measured in Seed Lab, Release build, % of one core (before → after):
workspace idle ~25 → ~2.8 · workspace with a held request ~25 → ~2.7 · hook card ~24 → ~4.5 · closed notch ~5.5 → ~1.7. Hidden notch stays 0.

What changed, in order of impact:
1. **Bug (mine, from the hook-card change):** `IslandRootView` keeps a view alive for every `IslandView` case, and the Seed mapping sent every unused case to `CoucouHubPane`, so 13 workspaces (13 Seeds) ran at once. Each case now maps to one view; unused cases are `EmptyView`, and `AppState.view` redirects Coucou-only views to the workspace in the Seed build. Ring "Settings" and Usage "settings" open the Seed Settings window.
2. Only the Seed on screen reacts and draws (`reacts` → `paused`); the workspace copy reacts only while the workspace is the visible view.
3. Seed no longer draws through SwiftUI per frame (profiling showed each TimelineView frame re-laid out and re-diffed the whole notch): `RiceMascotView` is an `NSViewRepresentable` around `RiceLayerView`, driven by its own `CADisplayLink`.
4. Drawing is Core Graphics (`RiceCanvas.swift`, GraphicsContext-shaped, blur via shadow). Shape-fixed parts (glows, aura, light pool, grain, rim line) are sprites at on-screen pixel density, composited as CALayers on the GPU (`RiceStage`); only eyes, cheeks, props and transient light are drawn live.
5. Frame pacing (`RiceMotion.pace`): 60 fps for quick springs, 30 for slow light and the last ease, 12 for the breath; ticks sooner than asked are skipped, and size changes wait for the next tick.
Verified: deterministic reference frames (`riceref` / `riceref layers` lab commands) match the old SwiftUI renderer; on-screen snapshots correct; Action Ring press/point still works; node 15/15; all Swift suites pass.
Research used: Canvas/TimelineView minimumInterval and static/dynamic split (swiftui-lab.com), TimelineView AutoLayout churn on macOS (Apple forum 773682), Core Animation offload for near-zero app CPU (camlittle.com, OpenNotch).
