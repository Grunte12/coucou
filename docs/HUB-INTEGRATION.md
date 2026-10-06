# Personal Coucou + Agent Tincan + LinkHub integration

This fork preserves Coucou as the native macOS notch UI. Official Agent Tincan
remains responsible for agent messaging and wake; Agent LinkHub remains the
tools-only MCP gateway. Neither upstream service is forked into the UI.

## Build boundary

`CoucouHub` builds the existing Coucou entry point, window, state machine,
character and hook UI with an embedded Tools / Activity / Tasks pane. That pane
reuses the existing Hub client and model rather than starting another window or
claiming agent inboxes. `COUCOU_HUB` confines the integration to this target.
The legacy `HubIsland` target is retained temporarily for rollback only; do not
install or run both targets together. The integrated target deliberately retains
the installed bundle identifier `com.hubisland.desktop` and output `HubIsland.app`.

```sh
cd NotchBuddy
xcodegen generate
xcodebuild -project NotchBuddy.xcodeproj -scheme CoucouHub \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/coucou-hub-build CODE_SIGNING_ALLOWED=NO build
bash scripts/test-hub-island-contract.sh
cd ..
node --test tests/CoucouHubIntegrationTests.mjs
```

The app uses the existing loopback-only Manager at `127.0.0.1:8768`. Install and
configure LinkHub and official Tincan separately. No tokens, private receiver
configuration or relay state are stored in this fork. Coding-agent hook setup
is an explicit operation through Coucou, not an automatic installer side effect.

## Behavioral guarantees retained

- One shared Hub model; metadata polling follows the existing 2s held / 10s
  healthy idle / 30s unavailable cadence. No LLM polling and no new inbox consumer.
- Hiding the Hub pane cancels panel-scoped detail reads/actions but not background
  metadata observation. Held count appears on Coucou's Hub button.
- Allow/Deny remains exact-request only with validated current detail and no
  automatic replay of uncertain outcomes. This is distinct from host-native
  coding-agent permission prompts and does not grant blanket authorization.
- Existing pairing and scoped Keychain lookup are reused. Deployment must retain
  the operator's stable signing identity; do not replace it with an ad-hoc build
  and claim cross-update Keychain access is preserved.

## Acceptance status

On 2026-10-06 the integrated macOS Debug target compiled successfully. Existing
contract/model/operator/geometry/sound fixture suites passed, and four added
build-boundary checks passed. No installed app, credentials, hooks, account
configuration or upstream runtime was replaced during these checks.

Still pending: actual native integrated-pane QA, signed replacement/relaunch of
the canonical app, and live integrated approval checks. Task-to-session dynamic
routing and routing controls are not implemented by this migration. Do not infer
these gates from a build or fixtures. The existing single-chat Codex wake adapter
is a separate local component and is not installed by this repository.

## Attribution and scope

Upstream: <https://github.com/Louis-CFM/coucou>. Preserve its MIT notices and
`LICENSE-ASSETS.md`. This is a personal integration fork, not an official Coucou
release. The character, branding, icons and sounds have separate asset terms;
do not publish a derivative app binary using them without the required permission.
macOS only for this integration; no iPhone or Windows implementation is added.
