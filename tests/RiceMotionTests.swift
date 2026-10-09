import Foundation

@main
struct RiceMotionTests {
    static var failures = 0
    static func check(_ ok: Bool, _ name: String) {
        if !ok { failures += 1; print("FAIL: \(name)") }
    }
    static func run(_ m: RiceMotion, seconds: Double, dt: Double = 1.0 / 60.0) {
        var left = seconds
        while left > 0 { m.step(min(dt, left)); left -= dt }
    }

    static func main() {
        // Spring: substeps, dt cap, convergence, retarget keeps position and velocity.
        var s = RiceSpring(0, 220, 19)
        s.to(1)
        s.step(10)                                   // capped at 50 ms
        check(s.v > 0 && s.v < 0.5, "one step never covers more than 50 ms")
        var a = RiceSpring(0), b = RiceSpring(0)
        a.to(1); b.to(1)
        a.step(0.05)
        for _ in 0..<6 { b.step(1.0 / 120.0) }
        check(abs(a.v - b.v) < 1e-9 && abs(a.vel - b.vel) < 1e-9, "50 ms equals six 1/120 s substeps")
        for _ in 0..<200 { a.step(0.05) }
        check(abs(a.v - 1) < 1e-3 && a.isSettled, "spring settles on target")
        var c = RiceSpring(0); c.to(1)
        for _ in 0..<5 { c.step(1.0 / 60.0) }
        let (pos, vel) = (c.v, c.vel)
        c.to(-1)
        check(c.v == pos && c.vel == vel, "retarget keeps position and velocity")
        c.step(-1)
        check(c.v == pos, "negative dt does nothing")

        // States: posture per state, interruptible, every state reachable.
        let m = RiceMotion(seed: 7)
        check(m.state == .idle, "starts idle")
        for st in RiceState.allCases {
            m.select(st)
            run(m, seconds: 3)
            check(m.weight(st) > 0.95, "\(st.name) weight reaches 1")
            let f = m.values()
            check(f.x.isFinite && f.y.isFinite && f.angle.isFinite && f.sx > 0.5 && f.sy > 0.5, "\(st.name) frame finite")
        }
        m.select(.resting); run(m, seconds: 3)
        check(m.values().angle < 0 && m.values().angle > -20, "resting dozes upright with a gentle lean")
        m.select(.approval); run(m, seconds: 0.1)
        let mid = m.v(.poseAngle)
        check(mid < -0.5 && mid > -7, "interrupt mid-flight continues from current angle")

        // Eyes stay inside the body for any pointer and any look.
        let g = RiceMotion(seed: 3)
        var maxN = 0.0
        for i in 0..<40 {
            let ang = Double(i) * 0.7
            g.pointer(dx: cos(ang) * 5000, dy: sin(ang) * 5000, range: 200, vx: 30, nearRadius: 40)
            if i % 10 == 0 { g.newApproval() }
            run(g, seconds: 0.2)
            let f = g.values()
            let gyv = f.ey < 0 ? 6 * 1.7 : 6
            maxN = max(maxN, hypot(f.ex / 9, f.ey / gyv))
        }
        check(maxN <= 1.0 + 1e-9, "eyes never leave the body (max \(maxN))")

        // Choreography tracks are cancellable; events are interruptible.
        let e = RiceMotion(seed: 11)
        e.dropIn()
        check(e.hasPending(.ev), "drop schedules its choreography")
        run(e, seconds: 0.2)
        e.reject()
        run(e, seconds: 0.1)
        check(e.file?.kind == .reject, "reject interrupts drop and takes the tile")
        e.cancel(.ev)
        check(!e.hasPending(.ev), "cancel clears the event track")
        run(e, seconds: 4)
        check(e.values().sx.isFinite, "settles after interrupted events")

        // Hover then drop in the same update: the gulp keeps the tile.
        let h = RiceMotion(seed: 5)
        h.startHover(); run(h, seconds: 0.5)
        h.scheduleEndHover()
        h.dropIn()
        check(!h.hasPending(.hover) && h.file?.kind == .drop, "drop cancels the pending hover end")
        run(h, seconds: 0.3)
        check(h.v(.fileA) > 0.5, "tile still visible during the gulp")

        // New request: startle, then the approval posture.
        let n = RiceMotion(seed: 9)
        n.newApproval()
        check(n.state == .idle, "startle comes before the state change")
        run(n, seconds: 0.3)
        check(n.state == .approval, "then approval")

        // Click spam builds up; hold squeezes deeper.
        let p = RiceMotion(seed: 2)
        p.pressDown(); run(p, seconds: 0.05)
        let sq1 = p.ch[RiceMotion.Ch.sqx.rawValue].t
        p.pressUp(); run(p, seconds: 0.05)
        p.pressDown(); p.pressUp(); p.pressDown()
        let sq3 = p.ch[RiceMotion.Ch.sqx.rawValue].t
        check(sq3 > sq1, "rapid clicks build up")
        p.pressUp()
        let q = RiceMotion(seed: 2)
        q.pressDown(); run(q, seconds: 0.5)
        check(abs(q.ch[RiceMotion.Ch.sqy.rawValue].t - 0.91) < 1e-9, "hold squeezes")
        q.pressUp(); run(q, seconds: 2)
        check(abs(q.v(.sqy) - 1) < 0.01, "release springs back")

        // Frame pacing: 60 fps only for quick springs, 30 for slow light, 12 for the breath.
        let f = RiceMotion(seed: 11)
        f.select(.idle)
        f.pressDown()
        check(f.pace == .full && abs(f.frameInterval - 1.0 / 60.0) < 1e-9, "a press runs at 60 fps")
        f.pressUp()
        var sawLight = false, sawBreath = false
        for _ in 0..<(60 * 20) {
            f.step(1.0 / 60.0)
            if f.pace == .light { sawLight = true }
            if f.pace == .breath { sawBreath = true }
        }
        check(sawLight, "slow light or the last ease drops to 30 fps")
        check(sawBreath, "a settled idle grain breathes at 12 fps")
        let o = RiceMotion(seed: 12)
        o.select(.working)
        run(o, seconds: 3)
        check(o.pace != .breath, "working never drops to the breath rate")

        // Pause: the clock stops and nothing moves.
        let z = RiceMotion(seed: 4)
        run(z, seconds: 1)
        let before = z.values()
        z.paused = true
        run(z, seconds: 2)
        let after = z.values()
        check(before.t == after.t && before.y == after.y && before.sx == after.sx, "pause stops the clock")
        check(!z.needsFrames, "paused needs no frames")
        z.paused = false
        run(z, seconds: 0.1)
        check(z.t > before.t, "resumes")

        // Reduce Motion: one snapped posture per state, no oscillation, no light, no tasks.
        let r = RiceMotion(seed: 8, reduced: true)
        check(r.pendingTaskCount == 0, "reduced idle schedules nothing")
        check(!r.needsFrames, "reduced idle needs no frames")
        for st in RiceState.allCases {
            r.select(st)
            r.step(0)
            let f0 = r.values()
            check(abs(r.weight(st) - 1) < 1e-9, "reduced \(st.name) snaps")
            check(r.pendingTaskCount == 0, "reduced \(st.name) has no tasks")
            var still = true
            for _ in 0..<120 { r.step(1.0 / 60.0); let f = r.values(); if f.y != f0.y || f.sx != f0.sx || f.angle != f0.angle || f.ex != f0.ex { still = false } }
            check(still, "reduced \(st.name) does not oscillate")
        }
        r.select(.idle)
        r.dropIn(); r.reject(); r.copied(); r.wake(); r.greet(); r.glanceToRail(); r.startHover(); r.pressDown()
        r.pointer(dx: 100, dy: 0, range: 200, vx: 0, nearRadius: 40)
        r.step(0.1)
        check(r.ripples.isEmpty && r.motes.isEmpty && r.rim == nil && r.zs.isEmpty && r.trail == nil, "reduced has no ripples, motes or light passes")
        check(r.pendingTaskCount == 0 && r.file == nil, "reduced events schedule nothing")
        r.newApproval()
        r.step(0)
        check(r.state == .approval, "reduced new request still shows approval")
        check(r.prop(.approval) == 1, "reduced approval prop shown at once")

        // Switching Reduce Motion on at runtime clears everything mid-motion.
        let live = RiceMotion(seed: 12)
        live.select(.working); live.dropIn(); run(live, seconds: 1.5)
        live.setReduced(true)
        check(live.pendingTaskCount == 0 && live.ripples.isEmpty && live.motes.isEmpty, "turning Reduce Motion on clears motion")
        live.setReduced(false)
        check(live.pendingTaskCount > 0, "turning it off restarts the state's life")

        // Light: motes are few and capped, ripples capped at 4.
        let l = RiceMotion(seed: 13)
        for _ in 0..<20 { l.mote(); l.ripple() }
        check(l.motes.count <= 6 && l.ripples.count <= 4, "light effects are capped")
        l.select(.idle)
        run(l, seconds: 30)
        check(l.isBored, "bored pose after 25 s untouched")
        l.touch()
        check(!l.isBored, "touch wakes the bored pose")

        // Long run stays bounded (no task or effect growth).
        let long = RiceMotion(seed: 21)
        for (i, st) in RiceState.allCases.enumerated() {
            long.select(st); run(long, seconds: 20, dt: 1.0 / 30.0)
            check(long.pendingTaskCount < 40, "tasks bounded in \(st.name) (\(long.pendingTaskCount))")
            _ = i
        }

        // Deterministic with a seed.
        let d1 = RiceMotion(seed: 99), d2 = RiceMotion(seed: 99)
        d1.select(.working); d2.select(.working)
        run(d1, seconds: 5); run(d2, seconds: 5)
        check(d1.values().y == d2.values().y, "seeded runs are deterministic")

        if failures == 0 { print("RiceMotion tests passed") } else { print("\(failures) failure(s)"); exit(1) }
    }
}
