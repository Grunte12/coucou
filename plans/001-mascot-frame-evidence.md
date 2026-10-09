# 001 — Capture dense, private mascot motion evidence

- **Status**: DONE — private reference/rice captures and bounded comparison complete; final character/UI design reserved for Claude after backend gates
- **Commit**: 1659072
- **Severity**: HIGH
- **Category**: Physicality / verification
- **Estimated scope**: isolated capture harness only; no production renderer edits

## Problem

The owner wants frame-level evidence before judging the original rice motion.
At audit start there were no dense contact sheets. A fixed dt alone is not deterministic for
the reference: `NotchBuddy/Sources/CoucouKit/BotEngine.swift:705` currently reads
`let now = CACurrentMediaTime()` in update; its eye drawing also reads wall time
at line1302. Random particle/lifetime values exist. Ordinary screenshots cannot
prove repeatable timing.

## Target

Capture the reference **for private study**, separately from product assets:

- Eleven states: idle, working, thinking, searching, approval, question, error,
  finished, ratelimit, sleeping, dizzy.
- Seven emotes: love, surprised, proud, wink, yawn, happy, annoyed.
- Explicit tap/squash and a repeatable cursor-left/right/up/down trajectory.
- Advance at1/120s, sample at30fps for2seconds per case (60frames). Label every
  tile with case and exact timestamp; include a320px reference and36/64px checks.
- Record renderer commit, seed/clock policy and uncaptured effects. If time/random
  injection cannot be isolated, label captures nondeterministic—never fake a seek.

Capture the rice's seven original states using `RiceMotion.frame(dt, reduced,
paused)` in `brand/rice/motion.mjs:46`, with the same timeline. Include mid-flight
state changes to inspect position/velocity continuity.

## Repo conventions to follow

`BotCanvasView.swift:3` uses TimelineView/Canvas, not video playback. The rice
preview uses an original SVG plus independent springs and imports no Mochi art.
Do not port the reference's paths, expression drawings or animation tables into
the rice renderer. Study motion principles, not protected character material.

## Steps

1. Build an isolated capture harness outside shipped source. Inspect the exact
   draw/state/emote signatures at the stamped commit; stop on drift.
2. For reference-only capture, inject a manual clock and seeded randomness into
   an isolated study copy, preserving attribution. Do not modify the installed
   app, hooks, agent state, approved artwork or live window.
3. Render/sample the listed cases; save originals and contact sheets in the
   private workspace
   `/Users/grunte/Documents/Codex/2026-07-26/v/outputs/mochi-motion-study/`,
   not product assets or Git history.
4. Render the original rice against the same timings; inspect settling, eye
   response, squash/rebound, clipping and36px readability.
5. Write a short measured comparison, with uncertainties and reproducible commands.

## Boundaries

No media-generation API, credits, source installs, production-app replacement,
account access, copied Mochi product assets, or claim of completed screenshots
before rendering. Do not change Coucou's theme or shell.

## Verification

- Mechanical: identical clock/seed input produces matching frame hashes; all
  cases/timestamps are present; no study assets are staged in Git.
- Feel check: inspect successive tiles and a10%-speed preview, especially the
  first160ms, rebound and interruption. Compare the36px eyes on black.
- Done when: actual sheets exist and have been visually reviewed. This plan and
  the source inventory alone do not satisfy the owner's request.

## Native reference capture evidence — 2026-10-06

Main's bounded comparison and limitations are recorded in
`/Users/grunte/Documents/Codex/2026-07-26/v/outputs/RICE_MOTION_REPAIR_ACCEPTANCE_20261006.md`.
Reference eye expressions/body deformation are visibly richer than the repaired
rice's subtle press; continuity passed but final soft-character quality did not.
This is evidence ready for Claude's design work, not native mascot acceptance.

- Source stamp validated: `HEAD` is `1659072`; the inspected BotEngine and
  renderer-support sources match that commit. The copy generator stops if the
  repository HEAD drifts.
- Built a private SwiftUI `ImageRenderer` harness under
  `/Users/grunte/Documents/Codex/2026-07-26/v/outputs/mochi-motion-study/`; it draws the original BotEngine pass sequence
  from an isolated copy. Only the copy injects a manual clock, seeded RNG, and
  deterministic callback scheduler. `MochiOutfitDrawing.swift` and
  `ColorHex.swift` are read-only compile inputs. Audio is stubbed; no app,
  project configuration, live window, credentials, or product files were used.
- `capture-1/` contains 21 cases × 60 actual 320×320 PNG frames (1,260 total),
  21 labeled contact sheets, and 36×36/64×64 MiniBot checks at 15/30s. Cases
  cover all 11 states, all 7 emotes, one tap/slap, a repeated left/up/right/
  down/center cursor route, and a squash interrupted by a second squash. Tiles
  are row-major and labeled by exact fractions `n/30s`, `n=1...60`.
- Three 10%-speed GIFs cover tap, cursor, and interrupted-squash motion.
  Representative sheets (`state_approval`, tap, cursor, interrupted squash)
  plus love/yawn emotes and both size overviews were visually inspected; the
  original 320px raw frames and exact hashes remain available for deeper review.
- Harness limitation: the isolated square canvas uses `particleOverhang=0`, so
  hearts/ZZZ at the upper edge may crop. Product placement, configured particle
  overhang, app shell, and notch clipping are intentionally not claimed.
- Bounded overscan repair:
  `/Users/grunte/Documents/Codex/2026-07-26/v/outputs/mochi-motion-study/overscan-1/`
  adds 3 cases
  (`emote_love`, `emote_yawn`, `state_sleeping`) × 60 actual 320×420 PNG frames
  plus timestamped contact sheets. Width remains 320px, retaining the logical
  body scale; the private viewport adds 100px of height and sets
  `particleOverhang=100`, shifting the body down 100px per BotEngine's draw
  formula. It does not scale the character, alter production code, or represent
  app-shell placement. The original 320×320 sheets remain unchanged as viewport
  checks.
- Inspected all three expanded contact sheets once: heart particles and ZZZs
  remain within the expanded viewport over the recorded timelines. The square
  320×320 viewport may still crop effects by design, and the overscan run does
  not claim to reproduce live app clipping or notch placement.
- Repeated the overscan simulation into `overscan-verify/` in hash-only mode;
  `diff -u overscan-1/frame-hashes.txt overscan-verify/frame-hashes.txt` was
  clean (all 180 pixel hashes matched). The overscan-only mode is reproducible
  using the commands in the private
  `/Users/grunte/Documents/Codex/2026-07-26/v/outputs/mochi-motion-study/README.md`.
- Repeated the full simulation in hash-only mode with the same clock and seed;
  `diff -u capture-1/frame-hashes.txt capture-verify/frame-hashes.txt` was
  clean (all 1,260 pixel hashes matched). The study workspace is outside the
  repository and no study frames or harness assets are staged in Git.
- Evidence index and reproduction notes are in
  `/Users/grunte/Documents/Codex/2026-07-26/v/outputs/mochi-motion-study/contact-index.md`
  and `README.md`.
- Pending: main-agent rice capture/contact index and cross-renderer comparison.
  Do not mark this plan DONE until that comparison and any remaining visual
  review are recorded.
