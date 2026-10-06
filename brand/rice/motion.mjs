// Original rice mascot physics. No Coucou artwork/character code is used.
export const poses = Object.freeze({
  idle: { x: 0, y: 0, angle: -28, sx: 1, sy: 1, gaze: 0, glow: .36 },
  thinking: { x: -4, y: -8, angle: -39, sx: .96, sy: 1.05, gaze: -3, glow: .48 },
  working: { x: 0, y: -3, angle: -16, sx: .94, sy: 1.08, gaze: 2, glow: .65 },
  sending: { x: 38, y: -10, angle: 12, sx: .91, sy: 1.12, gaze: 4, glow: .8 },
  approval: { x: 0, y: -6, angle: -8, sx: 1.06, sy: .95, gaze: 0, glow: .68 },
  done: { x: 0, y: -17, angle: -32, sx: 1.04, sy: .97, gaze: 0, glow: .75 },
  resting: { x: 0, y: 8, angle: -62, sx: 1.04, sy: .92, gaze: 0, glow: .2 },
});

export class Spring {
  constructor(value, stiffness = 170, damping = 25) {
    this.value = this.target = value;
    this.velocity = 0;
    this.stiffness = stiffness;
    this.damping = damping;
  }
  // Retargeting preserves both position and velocity, including interruptions.
  to(value) { this.target = value; }
  step(seconds) {
    let remaining = Math.max(0, Math.min(seconds, .05));
    while (remaining > 0) {
      const dt = Math.min(remaining, 1 / 120);
      this.velocity += (this.stiffness * (this.target - this.value) - this.damping * this.velocity) * dt;
      this.value += this.velocity * dt;
      remaining -= dt;
    }
    return this.value;
  }
  snap() { this.value = this.target; this.velocity = 0; }
}

export class RiceMotion {
  constructor() {
    this.state = 'idle';
    this.springs = Object.fromEntries(Object.entries(poses.idle).map(([k, v]) => [k, new Spring(v)]));
    this.elapsed = 0;
  }
  select(state) {
    if (!Object.hasOwn(poses, state)) return false;
    this.state = state;
    for (const [key, value] of Object.entries(poses[state])) this.springs[key].to(value);
    return true;
  }
  frame(dt, reduced = false, paused = false) {
    if (!paused) this.elapsed += Math.min(Math.max(dt, 0), .05);
    const values = Object.fromEntries(Object.entries(this.springs).map(([k, spring]) => {
      if (reduced) spring.snap(); else if (!paused) spring.step(dt);
      return [k, spring.value];
    }));
    if (!reduced && !paused) {
      const breath = Math.sin(this.elapsed * 2.3);
      values.sy *= 1 + breath * .012;
      values.sx *= 1 - breath * .009;
      values.y += Math.sin(this.elapsed * 1.7) * 1.6;
      if (this.state === 'working') values.angle += Math.sin(this.elapsed * 3.2) * 3;
    }
    return values;
  }
}
