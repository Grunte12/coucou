# Claude Code handoff — Notch workspace additions

Status: DISPATCHED AND ACCEPTED in the existing Code Coach session on 2026-10-06.
Native cross-session message `973f17e1-10a8-4f1b-a409-0c441536d2e7`; actual target
receipt is `CODE_COACH_HANDOFF_RECEIPT.md`, confirming conversation UUID
`ebefd411-714f-4d2c-b9c9-3dd291a52632` and handoff read. UI implementation is in
progress, not a completed acceptance gate. Backend acceptance passed. This is the
current owner brief; historical HubIsland UI handoffs are not visual authority.

## Owner boundary

Claude Code owns new UI/character design. Codex handles backend/integration and
verification first. Preserve the actual Coucou shell, controls, motion language,
sound settings and theme; do not reuse the old HubIsland dashboard or invent a
replacement visual world. Use the existing intended persistent Claude session
when identified, not a new CLI chat every time or the generic identity currently
working on unrelated Graphmory code.

## Features the owner requested

- Clipboard: local text/link/image/file items, choose and drag to another app.
  Explicit Copy is the fallback when the destination does not accept that drag
  type. No global keystroke injection or Accessibility requirement for paste.
- File shelf: drag downloaded/reference/output files into the notch, park them,
  drag them out to a chat/editor, reveal in Finder. Adding/removing a shelf entry
  must not move, overwrite or delete the original file. Sending to an agent is a
  separate explicit action, not a side effect of dropping a file.
- AI usage: short provider cards scroll horizontally. Show source/freshness and
  session/week reset details on demand. Only Claude's existing opt-in statusline
  relay is wired today; other providers must say unavailable, not guessed zero.
- Long messages, traces, settings and explanations scroll vertically. Keep the
  frame/header/mascot anchors consistent while switching panels/cards. Do not
  append all utilities to the already dense Agents header as tiny labels.

## Original mascot

Keep the owner-selected white/gold rice identity, but make the character soft,
expressive and readable: smooth gaze, interruptible squash/rebound and meaningful
eye feedback. A code-native 2D renderer is appropriate; no video or 3D dependency
is required. Motion-study evidence demonstrates principles, not reusable art.
Do not copy Coucou/Grok mascots, their paths, expression art or tween tables.
Reference: https://omninotch.app/#features and the owner's supplied screenshots.

## Backend boundary / integration points

- `CoucouWorkspaceStore.swift`: session-only file shelf and explicit opt-in
  clipboard service; initially disabled and no persistence/telemetry.
- `CoucouUsageSnapshot.swift`: validates the existing Claude `PlanUsage`; expired
  windows are stale, not proof a limit reset to empty. No credential reads.
- `CoucouHubIntegration.swift`: existing live Hub model remains presentation
  over the operator API. Official Tincan remains the message consumer.
- `FileDropView.swift`/`IslandWindowController.swift`: in COUCOU_HUB, file drops
  should stage locally rather than simulate an upload/copy animation.

Do not change bundle/signing/Keychain identity, hook configuration, permissions,
agent routing, API approval authority or paid/media actions. Keep one installed
app. Clipboard consent is an explicit UI choice; adding the backend must not
silently enable history. Do not promise password detection for arbitrary text.

## Acceptance before dispatch

- [x] File/clipboard backend tests pass using temporary files and a named test
  pasteboard only, never the owner's clipboard.
- [x] Usage snapshot tests pass: fresh/stale/unknown, invalid numbers, remaining
  percentage and expired reset semantics.
- [x] COUCOU_HUB drop/store wiring builds; no original-file copy/overwrite or
  fake remote upload occurs.
- [x] Existing Hub contract/integration tests remain green.
- [x] Genuine Claude Code session target is identified; native connector dispatch accepted and receipt verified.

Verification: Xcode CoucouHub Debug build exit0 (existing concurrency/deprecation
warnings remain); six Node integration checks and the full Swift contract/model/
operator/geometry/sound/AgentPane suite pass. Final workspace tests include
remote file-host rejection/localhost dedup and all named-pasteboard cases, with
no clipboard skips in the lead's scoped native run. Not installed yet; real
file/text/image drag to other apps is Claude UI acceptance, not a backend claim.

The owner authorized creation of the persistent `Code Coach — Notch UI` session.
Its CLI bootstrap read this brief, and official `claude --desktop --resume`
opened it in Desktop. A later CLI resume returned the same conversation UUID.
This proves creation/opening/resume, not live synchronization or Tincan delivery.
The generic Tincan receiver remains separate. The owner forbids computer use for
dispatch; an interrupted UI-send attempt is not an accepted implementation task.
Use supported session tools or CLI resume, not private socket injection, and
respect concurrent session writers and cross-session inbound controls.

## Claude UI acceptance (after dispatch)

Test empty/off/permission-denied/full/stale states; text/image/file drag to real
destinations and copy fallback; large content and provider names without changing
frame bounds; keyboard navigation/VoiceOver/Reduce Motion. Capture native panels,
not just static fixtures. Do not claim support for a provider/destination that
has not actually been exercised. Read supported APIs before expanding quota
sources; never scrape credentials as a convenience.
