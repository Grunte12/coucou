# 004 · Agent-to-agent timeline (replaces the Trail tab)

Status: built 2026-10-07 (SeedTimelineView, SeedTimelineLayout). Lab fixture `timeline`, tests in scripts/test-seed-timeline.sh.

## What it must answer at a glance
1. Who sent work to whom, in what order.
2. What is still open (held for approval, claimed, waiting for a reply).
3. Where to click to read one message, without opening everything.

## Formats considered

| Format | Shows order | Shows who→whom | Shows open work | Fits a 640×230 notch | Notes |
|---|---|---|---|---|---|
| **Swimlanes, time left→right** (one row per agent, curved arrow between rows per message) | yes | yes | yes, as a dot that has no return arrow yet | **best**: the notch is wide and short; 3–5 rows of ~32 pt fit | Same idea as trace waterfalls (Jaeger, Langfuse) turned sideways; the newest work sits at the right edge, next to "now". |
| Sequence diagram, time top→bottom (one column per agent) | yes | yes | yes | poor: tall format, ~5 messages visible before scrolling | The classic UML/Mermaid look; good in a big window, cramped in the notch. |
| Chat thread (bubbles left/right) | yes | only for 2 agents | partly | good | Very readable, but stops working with 3+ agents. |
| Trace tree / waterfall | nested calls | parent→child only | durations | ok | Built for nested spans; agent work here is peer-to-peer, not nested. |
| Arc or chord diagram | no | yes, aggregated | no | ok | Shows who talks most, loses time; could be a later "overview" mode. |

## Recommendation
**Horizontal swimlanes.**
- One row per agent: colour dot and name on the left, the same dot and name as the agent list.
- Time runs left→right, with the newest work at the right edge.
- Each message is a soft curved line from the sender's row to the recipient's row, drawn at the time it was sent.
- The line's state is shown by colour and texture:
  - held: amber, with a breathing dot at the head
  - claimed: solid
  - answered: a thin return curve
  - failed: red, dashed
- Click a line: it brightens, the others dim, and a detail card slides up from the bottom. The card shows the title, both agents, state and time, plus the message and reply bodies loaded on demand (the existing trace read, never polled). Approve and Deny appear only for a held request, behind the existing exact-request check.
- Scroll horizontally for history, with a "Now" pill to jump back. Two agents become a simple ping-pong between two rows.
- Seed reacts: when a new message arrives, Seed glances toward it; when a request is held, Seed takes its approval pose.

Two-agent case (the owner's example):
```
Claude Notch  ●───╮        ╭──────●        ╭──→
                  ╰─→●─────╯      ╰─→●─────╯
Codex Backend
              09:02     09:05      09:11   now
```

## Data
Everything needed is already in `HubTincanInbox.traces` and `.held` (sender, recipient, state, created_at, title). The bodies come from the existing `tincanTrace` call when an edge is opened. No new backend is needed for v1.

## Checks before building
- Drawn with `Canvas` and hit-tested per curve. Each edge has a VoiceOver element: "Codex Backend to Claude Notch, held, 09:05".
- Reduce Motion: no breathing dots and no slide; the card simply appears.
- The Seed Lab fixtures add a ten-message, three-agent scenario for snapshots.
