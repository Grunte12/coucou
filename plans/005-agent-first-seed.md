# 005 · Agent-first Seed: users' own agents customize the app

Status: owner's direction (2026-10-07), proposal only. This is backend and architecture work, so it needs Codex.

## Idea
Everyone installs the same Seed. Each person connects the coding agent they already use (Claude Code, Codex, Gemini CLI, Cursor, and others). That agent then reshapes Seed for them: which features appear, Seed's shortcuts, integrations such as Apple Music, YouTube or any MCP server, and the look within Seed's design language. The app does not offer a large settings screen. It offers:
1. a small, safe surface that agents can call,
2. a guide, as a skill, that teaches agents the design rules and how to use that surface,
3. Seed itself, which reacts to every change.

Tincan is optional. Seed must work without it. A "Proof" action (the owner's idea) can connect to the Tincan MCP for people who use it.

## Shape (proposal)
- **Seed exposes a local MCP server** on localhost only, opt-in, with a per-agent token kept in the Keychain. Tools:
  - `seed.describe()`: what the notch can hold, the current layout and the design tokens.
  - `seed.add_shortcut({title, symbol, action})`: adds an item to Seed's Action Ring (built 2026-10-07: `SeedRingStore`, today in UserDefaults `seed.ring.slots`, max 6; this tool would write the same list). Actions are limited to open URL, open app, reveal a folder, or run a command the user approved.
  - `seed.add_panel({kind, source, …})`: declarative panels such as a list, now-playing, status or file folder, filled from an MCP tool or a local file. No arbitrary UI code.
  - `seed.set_theme(tokens)`: colours and accents within the brand limits. Seed's shape and gold rim stay.
  - `seed.connect_integration(mcpServerConfig)`: always needs the user to confirm in the notch.
- **A single config file** (`~/Library/Application Support/Seed/seed.json`) is the source of truth. Agents edit it through the tools. Seed validates it, hot-reloads it, and keeps dated backups so any change can be undone.
- **Every change is visible.** Seed plays a short reaction and shows a "changed by Claude Code · Undo" toast. Anything that runs code, reaches the network or touches files needs one click from the user.
- **A skill file** (`SEED_SKILL.md`, shipped with the app and installable into agents) covers the design language, the spacing scale, do and don't, and examples.

## Fits the existing rules
- No telemetry.
- Network calls only to integrations the user connected.
- Secrets live in the Keychain.
- Nothing is approved or sent without an explicit click.

## Open questions for the owner
- Should the MCP server sit inside Seed or in a small helper process?
- Which panel kinds go in v1? Suggested: shortcut, list, now-playing and folder.
- How should a person share their setup? For example, export a `seed.json` theme pack.
