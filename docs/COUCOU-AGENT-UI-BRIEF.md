# Coucou agent workspace — UI implementation handoff

## Owner-approved direction

This is Coucou + official Agent Tincan + tools-only LinkHub, for personal macOS
use. Extend Coucou itself, not a Hub Island dashboard wearing Coucou chrome.
New pages, features, buttons and interactions are explicitly allowed; a new
theme or visual identity is not. Reuse the incumbent Mochi characters, layout
grammar, typography, materials, controls, motion, effects and sound vocabulary.
Inspect the upstream components and assets before adding new ones. Retain MIT
and asset notices. Do not publish an app binary with restricted assets.

The requested implementation model is **Claude Sonnet 5.5**. Before implementation,
verify the actual model available in this host. Do not silently substitute another
model. If the exact requested model cannot be selected, report that blocker to
Codex. Read installed Impeccable instructions fully and extend the established
world. Apply native-platform guidance where applicable. The owner also requested
taste and hallmark; use them only if installed and relevant to native SwiftUI,
otherwise disclose their absence without inventing instructions or a React port.

## Responsibility and collaboration

Claude owns the new Coucou UI and UI-only tests: `Sources/App` presentation,
navigation, Mochi/agent pills, settings presentation, and new SwiftUI views.
Codex owns Hub API/client/model contracts, operator security and deployment.
You are not alone in this checkout: preserve all existing changes, do not reset,
revert or overwrite another contributor's work. Ask Codex before changing client,
model, backend or permission contracts. Build with the `CoucouHub` target.

Remove irrelevant product integrations from the integrated target's presentation
and startup behavior (VS Code jump, Recents, Resend, n8n, Vercel, GitHub, etc.).
Do not delete upstream modules wholesale or alter the regular upstream target.
Keep ordinary coding-agent task/session observation where useful. Do not confuse
host-native coding permission prompts with Tincan held-request approvals.

Do not install another app, replace the running app, change signing, accounts,
keys, hooks, relay configuration or routing policy. No media generation or paid
provider calls. No blanket approvals, new inbox consumers or LLM polling.
Commit only your UI-owned files; report commit, tests and remaining gaps to Codex.
Codex handles the final combined commit/push and stable-signed deployment.

## Required surfaces

### Agents — Coucou Mochi/pills as the entry point

Represent real joined agents from `model.tincanRoster`, including the owner's
Muse, Grokbot, Codex, Cursor and other joined coding agents. Keep wire identities
unchanged; friendly display names are presentation only. Do not invent an online
Code-Coach/Goofy instance when no separate identity exists. Diagnostic test agents
may be hidden from the main row with a truthful all-agents disclosure.

Select an agent to show connection/presence, wake method, last active and queue
counts. Presence is not proof a task is executing. Distinguish offline, missing
configuration, unverified and unavailable. Connection/setup controls may open the
existing trusted operator/pairing flow; never display keys, solicit arbitrary
shell commands or implement a second credential store. Show a disabled action
with an honest explanation when its backend action does not exist yet.

### Communication — visualization first, details on click

Use sender/recipient/state/time from `model.tincanInbox.traces` and `.held` for
a bounded agent-to-agent visual timeline or connection trail in Coucou's style.
Do not show message title/body by default, even though legacy summaries have a
title. Treat trace rows as snapshots, not a complete event log: do not invent
each delivery/claim/reply animation from a single current state. Animate newly
observed IDs once; do not replay old history every refresh or tab switch.

Opening an exact transfer calls `model.readTincanTask(summary)` and reveals
the corresponding detail and event history only then. Use stable request IDs
and ordering, preserve selected agent/transfer across refreshes and provide back
navigation. No inbox claims, sends or routing changes are needed to visualize.
Do not present future task-to-session dynamic routing as implemented.

### MCP — compact truthful status

Use `model.snapshot.providers` for enabled/binding/health state and optional
recent jobs. Keep the primary surface informational and compact. Do not advertise
untested upstream tool capabilities as working. Use existing Manager controls
for configuration; do not create another MCP gateway inside the app.

### Review — exact-request approvals

Show waiting held requests and a compact badge, then explicit detail review.
Only enable Allow/Deny when `model.canDecideSelectedTincanTask` is true; dispatch
through `model.decideSelectedTincanTask`. Preserve current-ID checks, in-flight
disable, uncertain-outcome handling and no automatic POST retries. `needs_input`
is not an approve-able held request. Historical answered items are read-only.

## Existing integration and contracts

- One shared `CoucouHubIntegration.shared.model` (`HubIslandModel`). Preserve it;
  replace `CoucouHubPane`'s legacy `HubIslandDashboardView` composition, not the
  backend model. The old dashboard is transitional and explicitly rejected as
  the final visual authority.
- The Coucou host owns window/state machine/Mochi/sound. Keep one canonical app
  with bundle identity `com.hubisland.desktop`; no second window/controller app.
- Existing task metadata poller: 2s held, 10s healthy idle, 30s unavailable.
  Roster piggybacks at most once per 30s, no independent timer/agent wake.
- Hide/disappear cancels detail/action work with `model.panelHidden()`; background
  metadata remains. Collapse posts `.coucouHubCollapse` to the host controller.
- Local authenticated operator API, same existing pairing/Keychain identity:
  `GET /api/island/tincan` (task metadata),
  `GET /api/island/tincan/agents` (real roster),
  `GET /api/island/tincan/trace/{trace_id}` (explicit detail),
  `POST /api/island/tincan/decision` (exact held decision).
- Roster Swift types: `HubTincanRoster(status, enabled, agents)` and
  `HubTincanAgent(id, name, online, kind?, wake?, version?, lastActive?, queued,
  claimed)`. Nil roster means unverified/unavailable, not empty/online.
- Loopback-only Manager, existing `tincan:read`/`tincan:approve` scopes; no secrets,
  webhook targets or message bodies in the roster. Messaging remains official
  upstream Tincan, independently of tools-only LinkHub.

## Acceptance and evidence

Verify collapsed/expanded notch, multiple agent pills, tab/page changes, hover,
detail/back/collapse and settings with stable anchors: no icon jumping or stale
panels. Preserve Coucou spring/motion behavior and reduced-motion support. Long
names, zero agents, offline/unauthorized Manager, burst activity, loading/error
detail, held/needs_input/answered and unknown decision outcome must be usable.
Keep animation lightweight and do not use continuous loops for idle history.

Build plus existing contract tests are required. Use isolated fixtures for UI
approval scenarios; do not approve real queued work merely to test. Capture
private screenshots for review, not GitHub publication. Review in bounded passes
using Impeccable's native workflow. Return evidence and open issues honestly.

Baseline verified by Codex on 2026-10-06: CoucouHub compiled; Swift contract/model/
operator/geometry/sound suites and four integration boundary tests passed;
backend operator/roster/island tests passed (38 cases); real read-only upstream
roster returned eight joined identities. Live held decisions in the redesigned
UI and session routing are not verified by those tests.
