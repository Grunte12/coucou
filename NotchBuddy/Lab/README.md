# Seed Lab

Runs the real Seed notch views (`IslandRootView`, expanded on the agent
workspace) in an ordinary window with fixture data, so an agent can drive and
check the UI without anyone holding the notch open.

```
scripts/seed-lab.sh [--no-build] [--release] [--visible] OUT_DIR walkthrough.lab
scripts/seed-lab.sh OUT_DIR -e "fixture approval; expand; wait 1; snap agents grid"
```

- Own bundle id `com.grunte.seed.lab`: separate preferences, no Keychain,
  never installed, never touches the installed app.
- Fixture Hub API (`SeedLabFixtures.swift`): no network; approve/deny are
  recorded in `report.json` and go nowhere.
- Private pasteboard: the user's clipboard is never read or written.
- Snapshots come from the lab's own window (`cacheDisplay`), never the screen.
  The window sits behind other windows unless `--visible`.

## Rice Motion Lab v3

`scripts/seed-lab.sh --rice` opens a window with the real Swift mascot: every
state and event as buttons, live pointer gaze, press squash, notch size or
large, Reduce Motion. It replaces `brand/rice/motion-lab.html` (v2) for review.
`--rice --snap FILE` renders it behind other windows and saves a PNG.

## Commands

Coordinates are window points from the top-left of the 720×320 panel; the
expanded notch starts at x = 40. Full snapshots are @2x.

| Command | Does |
|---|---|
| `expand` / `collapse` | open the agent workspace / go compact |
| `fixture calm\|busy\|approval\|offline\|empty` | swap Hub data and refresh |
| `section agents\|shelf\|clipboard\|usage` | switch section (as the host does) |
| `click X Y`, `press X Y [s]`, `move X Y [steps]`, `leave` | in-process mouse events |
| `scroll X Y DY [DX]` | scroll wheel at a point |
| `drop N`, `unlink`, `dragover on\|off` | shelf: park fixture files, delete one original, drag hover |
| `copy text\|url\|image\|file\|private\|clear [payload]` | write the lab pasteboard |
| `history on\|off` | clipboard history |
| `usage none\|fresh\|high\|stale\|passed`, `relay on\|off` | Claude plan usage |
| `snap NAME [grid] [crop=x,y,w,h]` | PNG; `grid` adds a 20 pt grid with labels |
| `settings PAGE [HEIGHT]` | PNG of Seed Settings on one page (general, agents, ring, folders, about), 720 wide |
| `film NAME SECONDS FPS COLS [crop=…]` | frames over time in one contact sheet |
| `cpu SECONDS LABEL` | this process's CPU, appended to `cpu.txt` |
| `wait S`, `log TEXT` | |

`SEED_LAB_FREEZE_RICE=1` holds the mascot still, to measure the rest of the pane.

## What it cannot check

Real notch placement on a notched screen, real hover tracking (the lab feeds the
same gaze handler directly), drags into other apps, VoiceOver, and macOS
permission prompts. CPU numbers include the lab window, which stays on screen in
every mode; compare states against each other, not against the installed app.
