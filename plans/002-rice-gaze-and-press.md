# 002 — Smooth rice gaze and make press feedback interruptible

- **Status**: DONE — prototype physics/event tests and actual browser-frame checks pass; native mascot integration and final character design remain separate
- **Commit**: 1659072
- **Severity**: MEDIUM
- **Category**: Physicality / interruptibility
- **Estimated scope**: brand/rice/motion.mjs, preview.html, motion.test.mjs

## Problem

`brand/rice/preview.html:84-87` writes gaze directly from pointer coordinates;
line97 immediately renders `translate(${gaze+v.gaze} ${gazeY})`. This bypasses
the prototype's otherwise continuous spring response. Pointer-down at lines88-91
directly overwrites scale velocity. Actual softness/volume still needs the dense
rendered evidence in plan001; do not claim it from code alone.

## Target

Reuse the original Spring(value,170,25) implementation, which preserves position
and velocity on `.to(value)` (`motion.mjs:12-31`). Keep existing state trajectories.

- Independent cursor springs target the current bounded offsets: horizontal±3,
  vertical±2. Pointerleave retargets to0; it does not snap.
- Use one separate press multiplier spring,1→0.97. Render scaleY multiplied by
  press and scaleX divided by press, retaining approximate area. Release/cancel
  retargets to1 from current position/velocity.0.97 comes from the motion audit's
  subtle press-feedback guidance, not the reference character's squash table.
- Reduced motion snaps cursor/press feedback; pause freezes it. Hidden tabs stop
  rendering. Preserve the50ms cap and1/120s substeps.
- Keep all seven states, original white/gold vectors and dark preview shell.

## Repo conventions to follow

State retargeting already carries velocity (`motion.mjs:40-45`). Do not replace
it with CSS keyframes or reset the pose on every event. The existing three Node
tests verify interruption, finite convergence, reduced motion and bounded resume.

## Steps

1. Add cursorX/cursorY and press channels to RiceMotion, outside the state-pose
   dictionary so selecting a state does not overwrite pointer targets.
2. Return these channels from frame with the same pause/reduced-motion behavior.
3. Pointermove calls target setters; pointerleave resets cursor targets. Bind
   pointerdown/up/cancel to press target setters. Keep keyboard activation usable;
   never leave press engaged after focus loss or cancelled input.
4. Compose cursor with existing state gaze and press with the existing scale in
   the render function. No unbounded transform, new animation dependency or timer.
5. Add assertions for continuity after100 fast gaze/press reversals, convergence,
   pause/reduced motion, cancellation and combined state changes.

## Boundaries

Do not change Coucou UI, agent routing, permissions, installed app, sounds,
SVG silhouette or branding. Do not copy BotEngine character drawing/tween tables.
If the stamped code has drifted, stop and reconcile instead of overwriting it.

## Verification

- Mechanical: `node --test brand/rice/motion.test.mjs` passes all old/new cases.
- Feel check: move cursor across the grain, stop abruptly, leave it, press/release
  during a state transition; no gaze snap, trapped press or teleport. Inspect at
  slow speed and36/64px. Reduced motion removes movement but keeps clear feedback.
- Done when: tests and actual rendered interaction evidence pass. A prototype
  improvement is not a finished native app mascot or commercial clearance.
