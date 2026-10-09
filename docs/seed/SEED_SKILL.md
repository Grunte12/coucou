---
name: seed
description: Customize Seed, the macOS notch workspace, for its user. Use when the user asks their agent to change Seed's Action Ring, pin folders, or wants something added to Seed. Covers what can be changed today, how, and Seed's design rules.
---

# Seed: a guide for the user's agent

Seed is a notch workspace on the user's Mac. **Seed** is also its only character: a glowing white rice grain with a gold rim, in the notch's top-left corner. The user taps Seed to open the Action Ring.

The user customizes Seed by asking you, their agent. Your job is to make small, reversible changes that suit them, inside Seed's design language.

## What you can change today

Both settings below live in Seed's preferences domain, `com.grunte.seed`. Seed reads them again each time the ring opens or the Folders section appears, so no restart is needed.

### Action Ring (up to 6 actions, first = top of the fan)

Set the ring:

```bash
defaults write com.grunte.seed seed.ring.slots -array timeline review shelf folders clipboard usage
```

Read the current ring:

```bash
defaults read com.grunte.seed seed.ring.slots
```

Available ids:

| id | What it does |
|---|---|
| `agents` | Opens the agent list |
| `timeline` | Opens the agent-to-agent timeline |
| `review` | Opens requests held for approval |
| `mcp` | Opens MCP/Hub status |
| `shelf` | Opens staged files |
| `folders` | Opens pinned folders |
| `clipboard` | Opens the clipboard |
| `usage` | Opens AI plan usage |
| `refresh` | Refreshes agents |
| `manager` | Opens the Hub Manager in the browser |
| `sound` | Turns sounds on or off |
| `settings` | Opens Settings |

How Seed reads the list:
- Unknown ids are ignored.
- Duplicates are dropped.
- An empty list falls back to the defaults.

### Pinned folders (up to 8)

Set the pins:

```bash
defaults write com.grunte.seed seed.folders.pins -array "$HOME/Code/my-app" "$HOME/Documents/Specs"
```

How Seed reads the list:
- Only existing folders are kept.
- Seed only lists their contents. It never moves, renames or deletes anything in them.

## Always

- **Ask before changing**, and say exactly what you will write.
- **Read the current value first**, so you can tell the user how to undo the change.
- **Keep it small.** Seed is "minimal, details on demand". Fewer, well-chosen actions beat a full ring.

## Never

- Add a second character, or reshape or recolour Seed itself. The white grain, gold rim and gold aura are the brand.
- Add anything that copies a built-in macOS feature, such as screenshots or screen recording.
- Write outside Seed's preferences, or put secrets in them. Secrets live in the Keychain only.
- Approve or deny an agent request for the user. That always needs the user's own click in the notch.

## Design language (for anything you propose)

### Colour

| Role | Hex |
|---|---|
| Background | `#0E0F11` |
| Raised surface | `#131518` |
| Text | `#F5F6F8` |
| Secondary text | `#C5C8CD` |
| Muted text | `#8E939C` |
| Faint text | `#6B7079` |
| Accent: Seed gold, used for focus and selection | `#F5C542` |
| Waiting for you | `#F5A524` (amber) |
| Working | `#22D3EE` (cyan) |
| Done | `#22C55E` (green) |
| Failed | `#F4505E` (red) |

### Spacing and type

- Spacing uses 4, 8, 12 and 16 pt: 8 between rows, 12 between sections.
- Type is the system font, 10–13 pt, with numbers set in monospaced digits.

### Motion

- Soft springs, roughly 0.3 s response and 0.8 damping.
- Nothing loops forever except a slow pulse on something that waits for the user.
- Respect Reduce Motion.

### Hover

- A gold wash or a gold hairline.
- Never a grey outline or end bars.

### Seed reacts to what happens

| Event | Seed's reaction |
|---|---|
| A file arrives | Catches it |
| A request is held | Looks alert |
| A message passes between agents | Glances at the timeline |

Changes you make through settings show up the same way as the user's own.

## Coming later (plan 005)

A local, opt-in Seed MCP server with these tools:
- `seed.describe`
- `seed.add_shortcut`, which will write the same ring list
- `seed.add_panel`
- `seed.set_theme`
- `seed.connect_integration`

Each change will show a "changed by your agent · Undo" toast. Until then, use only the settings above.
