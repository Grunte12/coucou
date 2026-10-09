#if COUCOU_HUB
import Foundation

// Rice mascot motion, ported from brand/rice/motion-lab.html (v4), our own
// original art and choreography. Foundation only, so it is unit-testable with
// swiftc (scripts/test-rice-motion.sh). Drawing lives in RiceMascotView.swift.
//
// Owner's lab choices baked in as defaults: spring "soft", light "normal",
// motes "few", wai "bow only", sending lean "small", gaze "normal",
// click spam "builds up", bored pose "keep". No captions.

/// Damped spring. Retargeting keeps position and velocity, so every motion
/// can be interrupted mid-flight without a jump.
struct RiceSpring {
    var v: Double
    var t: Double
    var vel: Double = 0
    var k: Double
    var c: Double

    init(_ v: Double, _ k: Double = 170, _ c: Double = 25) {
        self.v = v; self.t = v; self.k = k; self.c = c
    }

    mutating func to(_ target: Double) { t = target }
    mutating func kick(_ x: Double) { vel += x }
    mutating func snap() { v = t; vel = 0 }

    /// Integrates in substeps of at most 1/120 s; one call never covers more than 50 ms.
    mutating func step(_ seconds: Double) {
        var r = min(max(seconds, 0), 0.05)
        while r > 1e-9 {
            let d = min(r, 1.0 / 120.0)
            vel += (k * (t - v) - c * vel) * d
            v += vel * d
            r -= d
        }
    }

    var isSettled: Bool { abs(t - v) < 1e-3 && abs(vel) < 1e-3 }
    /// Still easing in, but too slowly for 60 fps to look any different.
    var isCalm: Bool { abs(t - v) < 0.02 && abs(vel) < 0.08 }
}

enum RiceState: Int, CaseIterable, Sendable {
    case idle, thinking, working, sending, approval, done, resting

    var name: String {
        switch self {
        case .idle: return "idle"
        case .thinking: return "thinking"
        case .working: return "working"
        case .sending: return "sending"
        case .approval: return "approval"
        case .done: return "done"
        case .resting: return "resting"
        }
    }
}

/// Posture first: each intent has its own silhouette even with every animation off.
struct RicePose: Sendable {
    let x, y, angle, sx, sy, glow, eye, blush: Double

    static func of(_ s: RiceState) -> RicePose {
        switch s {
        case .idle:     return RicePose(x: 0, y: 0, angle: -4, sx: 1, sy: 1, glow: 0.7, eye: 1, blush: 0.16)
        case .thinking: return RicePose(x: 2, y: -4, angle: -11, sx: 0.97, sy: 1.04, glow: 0.5, eye: 0.95, blush: 0.1)
        case .working:  return RicePose(x: 0, y: 3, angle: 5, sx: 1.05, sy: 0.95, glow: 0.8, eye: 0.82, blush: 0.12)
        case .sending:  return RicePose(x: 2, y: -2, angle: 8, sx: 0.98, sy: 1.02, glow: 0.85, eye: 0.95, blush: 0.12)
        case .approval: return RicePose(x: 0, y: -5, angle: 0, sx: 0.97, sy: 1.05, glow: 0.85, eye: 1.15, blush: 0.08)
        case .done:     return RicePose(x: 0, y: -3, angle: 0, sx: 1.02, sy: 0.99, glow: 0.95, eye: 1, blush: 0.55)
        case .resting:  return RicePose(x: -1, y: 4, angle: -7, sx: 1.03, sy: 0.96, glow: 0.3, eye: 0.1, blush: 0.2)
        }
    }
}

/// The owner's lab choices. Defaults are the approved ones.
struct RiceSettings: Sendable {
    var springK: Double = 220, springC: Double = 19   // "soft"
    var light: Double = 1                             // "normal"
    var motes = true                                  // "few"
    var gazeX: Double = 9, gazeY: Double = 6          // "normal"
    var sendLean: Double = 3                          // "small"
    var spamBuildsUp = true                           // "builds up"
    var boredPose = true                              // "keep"
}

/// Deterministic, allocation-free random source (SplitMix64) so tests can seed it.
struct RiceRandom {
    private var s: UInt64
    init(seed: UInt64) { s = seed }
    mutating func next() -> Double {
        s &+= 0x9E37_79B9_7F4A_7C15
        var z = s
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z = z ^ (z >> 31)
        return Double(z >> 11) / Double(1 << 53)
    }
    mutating func range(_ a: Double, _ b: Double) -> Double { a + next() * (b - a) }
}

/// The values the painter needs for one frame (rice units, see RiceMascotView).
struct RiceFrame: Sendable {
    var x = 0.0, y = 0.0, angle = 0.0, sx = 1.0, sy = 1.0
    var ex = 0.0, ey = 0.0, eyeOpen = 1.0, glow = 0.0
    var blush = 0.0, smile = 0.0, sleep = 0.0
    var t = 0.0
    var reduced = false
    var resting = 0.0
}

enum RiceRippleColor: Sendable { case gold, amber, white }

final class RiceMotion {
    // ----- channels -----
    enum Ch: Int, CaseIterable {
        case poseX, poseY, poseAngle, poseSX, poseSY, poseGlow, poseEye
        case curX, curY, lookX, lookY, lean, tilt, shakeA
        case sqx, sqy, scale, hop, bow, stretch
        case blink, boost, blush, smile, sleep
        case flare, dim, check, lotus, recv, fileA
        case hmm, dip, send, tip
    }
    enum Track { case st, ev, bk, hold, hover }

    struct Ripple { var t0, dur, str, size: Double; var col: RiceRippleColor; var inward: Bool }
    struct Rim { var t0, dur, str, p0, span, len: Double }
    struct Mote { var t0, x, y, vy, life, r, ph: Double }
    struct Zee { var t0, dur: Double }
    struct Trail { var t0, dur, ox, oy: Double }
    enum FileKind { case hover, drop, reject }
    struct FileMotion { var kind: FileKind; var t0, fx, fy, frot: Double }
    struct FileTile { var x, y, rot, s, o: Double }

    private struct Task { let track: Track; let t: Double; let fn: (RiceMotion) -> Void }

    var settings: RiceSettings
    private var rng: RiceRandom

    private(set) var ch: [RiceSpring]
    private(set) var w: [RiceSpring]    // state weights
    private(set) var pr: [RiceSpring]   // per-state props
    private(set) var state: RiceState = .idle
    private(set) var t: Double = 0
    private var tasks: [Task] = []
    private var nextTaskTime = Double.infinity

    private(set) var ripples: [Ripple] = []
    private(set) var rim: Rim?
    private(set) var motes: [Mote] = []
    private(set) var zs: [Zee] = []
    private(set) var trail: Trail?
    private(set) var file: FileMotion?

    private(set) var reduced = false
    /// Pause: the mascot's clock stops; nothing advances.
    var paused = false
    private(set) var isBored = false
    private var idleSince: Double = 0
    private var nextBlink: Double
    private var lastX = 0.0, lastY = 0.0
    private var clicks: [Double] = []
    private var held = false

    init(seed: UInt64 = UInt64(truncatingIfNeeded: Int(Date().timeIntervalSince1970 * 1000)),
         settings: RiceSettings = RiceSettings(), reduced: Bool = false) {
        self.settings = settings
        self.rng = RiceRandom(seed: seed)
        let p = RicePose.of(.idle)
        var c = [RiceSpring](repeating: RiceSpring(0), count: Ch.allCases.count)
        func set(_ k: Ch, _ v: Double, _ s: Double, _ d: Double) { c[k.rawValue] = RiceSpring(v, s, d) }
        set(.poseX, p.x, 150, 24); set(.poseY, p.y, 150, 24); set(.poseAngle, p.angle, 150, 24)
        set(.poseSX, p.sx, 150, 24); set(.poseSY, p.sy, 150, 24); set(.poseGlow, p.glow, 150, 24); set(.poseEye, p.eye, 150, 24)
        set(.curX, 0, 170, 24); set(.curY, 0, 170, 24); set(.lookX, 0, 150, 24); set(.lookY, 0, 150, 24)
        set(.lean, 0, 140, 23); set(.tilt, 0, 120, 20); set(.shakeA, 0, 200, 17)
        set(.sqx, 1, settings.springK, settings.springC); set(.sqy, 1, settings.springK, settings.springC)
        set(.scale, 1, 200, 22); set(.hop, 0, 160, 20); set(.bow, 0, 90, 19); set(.stretch, 0, 170, 24)
        set(.blink, 1, 420, 34); set(.boost, 0, 150, 24); set(.blush, p.blush, 150, 24); set(.smile, 0, 200, 26); set(.sleep, 0, 170, 26)
        set(.flare, 0, 140, 20); set(.dim, 0, 150, 24); set(.check, 0, 180, 20); set(.lotus, 0, 180, 22)
        set(.recv, 0, 150, 24); set(.fileA, 0, 260, 30)
        set(.hmm, 0, 90, 19); set(.dip, 0, 320, 32); set(.send, 0, 150, 22); set(.tip, 0, 200, 22)
        ch = c
        w = RiceState.allCases.map { RiceSpring($0 == .idle ? 1 : 0, 150, 24) }
        pr = RiceState.allCases.map { _ in RiceSpring(0, 180, 20) }
        nextBlink = 0
        nextBlink = rng.range(2, 4)
        self.reduced = reduced
        select(.idle)
    }

    // MARK: channel helpers

    func v(_ k: Ch) -> Double { ch[k.rawValue].v }
    private func to(_ k: Ch, _ x: Double) { ch[k.rawValue].to(x) }
    private func kick(_ k: Ch, _ x: Double) { ch[k.rawValue].kick(x) }
    func weight(_ s: RiceState) -> Double { min(1, max(0, w[s.rawValue].v)) }
    func prop(_ s: RiceState) -> Double { pr[s.rawValue].v }
    private func rand(_ a: Double, _ b: Double) -> Double { rng.range(a, b) }
    private func chance(_ p: Double) -> Bool { rng.next() < p }

    // MARK: timeline (on the mascot's own clock; cancellable per track)

    private func at(_ track: Track, _ delay: Double, _ fn: @escaping (RiceMotion) -> Void) {
        let due = t + delay
        tasks.append(Task(track: track, t: due, fn: fn))
        if due < nextTaskTime { nextTaskTime = due }
    }
    func cancel(_ track: Track) {
        tasks.removeAll { $0.track == track }
        nextTaskTime = tasks.reduce(Double.infinity) { min($0, $1.t) }
    }
    var pendingTaskCount: Int { tasks.count }
    func hasPending(_ track: Track) -> Bool { tasks.contains { $0.track == track } }

    /// Repeats `fn` while `state` stays current. Never scheduled with Reduce Motion.
    private func every(_ s: RiceState, _ lo: Double, _ hi: Double, first: Double? = nil,
                       _ fn: @escaping (RiceMotion) -> Void) {
        guard !reduced else { return }
        at(.st, first ?? rand(lo, hi)) { m in
            guard m.state == s, !m.reduced else { return }
            fn(m)
            m.every(s, lo, hi, fn)
        }
    }

    // MARK: brand light language

    func ripple(dur: Double = 1.8, str: Double = 0.6, size: Double = 0.5,
                col: RiceRippleColor = .gold, inward: Bool = false) {
        guard !reduced else { return }
        ripples.append(Ripple(t0: t, dur: dur, str: str, size: size, col: col, inward: inward))
        if ripples.count > 4 { ripples.removeFirst() }
    }
    func rimPass(dur: Double = 1.7, str: Double = 0.7) {
        guard !reduced else { return }
        rim = Rim(t0: t, dur: dur, str: str, p0: rand(82, 92), span: rand(40, 52), len: 15)
    }
    func mote(fromTop: Bool = false) {
        guard !reduced, settings.motes, motes.count < 6 else { return }
        if fromTop {
            motes.append(Mote(t0: t, x: rand(-24, 24), y: -80, vy: -rand(11, 15), life: rand(2.4, 3), r: rand(2.2, 3), ph: rand(0, 6)))
        } else {
            let side: Double = chance(0.5) ? -1 : 1
            motes.append(Mote(t0: t, x: side * rand(46, 56), y: rand(-40, 6), vy: -rand(9, 13), life: rand(3, 4.2), r: rand(2.2, 3.2), ph: rand(0, 6)))
        }
    }
    private func zz() {
        guard !reduced else { return }
        zs.append(Zee(t0: t, dur: 3.6))
        if zs.count > 2 { zs.removeFirst() }
    }
    private func sendTrail() {
        guard !reduced else { return }
        trail = Trail(t0: t, dur: 1.5, ox: lastX * 3 / 1.4 + 44, oy: lastY * 3 / 1.4 - 12)
    }

    // MARK: state

    func select(_ name: RiceState, replay: Bool = false) {
        let changed = state != name || replay
        cancel(.st)
        state = name
        let p = RicePose.of(name)
        to(.poseX, p.x); to(.poseY, p.y); to(.poseAngle, p.angle); to(.poseSX, p.sx); to(.poseSY, p.sy)
        to(.poseGlow, p.glow); to(.poseEye, p.eye)
        for s in RiceState.allCases { w[s.rawValue].to(s == name ? 1 : 0); pr[s.rawValue].to(0) }
        for k in [Ch.hmm, .dip, .send, .tip] { to(k, 0) }
        to(.blush, p.blush); to(.smile, name == .done ? 1 : 0); to(.sleep, name == .resting ? 1 : 0)
        to(.check, 0); to(.lotus, 0); to(.bow, 0)
        let PR = name.rawValue
        if reduced {
            // One snapped posture per state: no phrases, no light, no loops.
            if name != .idle { pr[PR].to(1) }
            if name == .done { to(.check, 1) }
            return
        }
        switch name {
        case .idle:
            every(.idle, 6, 11, first: rand(1.5, 3)) { $0.rimPass(dur: 1.8, str: 0.55) }
            every(.idle, 5, 9, first: rand(2.5, 4)) { $0.mote() }
        case .thinking:
            at(.st, 0.25) { $0.pr[PR].to(1) }
            every(.thinking, 3.4, 5.2, first: 1.4) { m in
                m.to(.hmm, 1); m.at(.st, m.rand(1, 1.4)) { $0.to(.hmm, 0) }
            }
        case .working:
            pr[PR].to(1)
            at(.st, 0.5) { $0.typing() }
            every(.working, 2.6, 4.2, first: 0.8) { $0.rimPass(dur: 1.15, str: 0.7) }
            every(.working, 1.8, 3, first: 1.2) { $0.mote(fromTop: true) }
        case .sending:
            pr[PR].to(1)
            at(.st, 0.3) { $0.sendPhrase() }
        case .approval:
            pr[PR].to(1)
            every(.approval, 5, 7, first: rand(2.4, 3.2)) { $0.politeRise() }
        case .done:
            if changed { doneIntro() } else { to(.check, 1) }
            every(.done, 5, 8, first: 3.8) { $0.rimPass(dur: 1.9, str: 0.6) }
            every(.done, 3, 5, first: 2.6) { $0.mote() }
        case .resting:
            pr[PR].to(1)
            every(.resting, 3.6, 5.2, first: 0.8) { $0.zz() }
            // Dozing upright: now and then the grain nods off and slowly lifts again.
            every(.resting, 6, 9, first: 2.4) { m in
                m.to(.bow, 0.5)
                m.at(.st, 1.3) { $0.to(.bow, 0) }
            }
        }
    }

    /// Working: short typing phrases of 3-5 quiet dips, then a rest; never a fixed beat.
    private func typing() {
        guard state == .working, !reduced else { return }
        let n = 3 + Int(rand(0, 3))
        var tt = 0.0
        for _ in 0..<n {
            at(.st, tt) { $0.to(.dip, 1) }
            at(.st, tt + 0.13) { $0.to(.dip, 0) }
            tt += rand(0.27, 0.37)
        }
        if chance(0.5) {
            let d = rand(0.5, 0.9) * (chance(0.5) ? -1 : 1)
            at(.st, tt) { $0.to(.lookX, d) }
            at(.st, tt + 0.9) { $0.to(.lookX, 0) }
        }
        at(.st, tt + rand(0.9, 1.8)) { $0.typing() }
    }

    /// Sending: gather, release (the glow flows out as a trail), settle, long hold.
    private func sendPhrase() {
        guard state == .sending, !reduced else { return }
        to(.send, -1)
        at(.st, 0.5) { m in m.to(.send, 1); m.sendTrail(); m.to(.dim, 0.15); m.to(.lookX, 1.3) }
        at(.st, 1.0) { $0.to(.send, 0) }
        at(.st, 1.7) { m in m.to(.lookX, 0); m.to(.dim, 0) }
        at(.st, rand(3.4, 4.4)) { $0.sendPhrase() }
    }

    private func politeRise() {
        to(.tip, 1)
        at(.st, 0.38) { $0.to(.tip, 0) }
        ripple(dur: 2.1, str: 0.55, size: 0.45, col: .amber)
    }

    private func doneIntro() {
        to(.sqx, 1.06); to(.sqy, 0.92); to(.smile, 1)
        at(.st, 0.32) { m in
            m.to(.sqx, 1); m.to(.sqy, 1); m.kick(.sqy, 2.2); m.kick(.sqx, -1.6); m.kick(.hop, -110)
            m.to(.check, 1); m.kick(.flare, 3); m.ripple(dur: 2.1, str: 0.7, size: 0.6)
        }
        at(.st, 0.9) { m in m.kick(.sqx, 1); m.kick(.sqy, -1.3) }
        at(.st, 1.35) { $0.wai(.st) }
    }

    /// Thai wai: a slow bow with happy eyes, a light pass over the rim, warm motes rising.
    /// "Bow only": the lotus bud stays off.
    func wai(_ track: Track = .ev) {
        guard !reduced else { return }
        to(.smile, 1); to(.bow, 1); to(.lotus, 0); to(.blush, 0.55); rimPass(dur: 1.9, str: 0.8)
        at(track, 0.5) { m in m.mote(); m.mote() }
        at(track, 1.25) { $0.to(.bow, 0) }
        at(track, 1.9) { m in
            m.to(.lotus, 0)
            if m.state != .done { m.to(.smile, 0) }
            m.to(.blush, RicePose.of(m.state).blush)
        }
    }

    func resetEv() {
        cancel(.ev)
        let p = RicePose.of(state)
        to(.sqx, 1); to(.sqy, 1); to(.scale, 1); to(.hop, 0); to(.bow, 0); to(.stretch, 0)
        to(.lookX, 0); to(.lookY, 0); to(.lean, 0); to(.tilt, 0); to(.shakeA, 0)
        to(.boost, 0); to(.blink, 1); to(.dim, 0); to(.recv, 0); to(.fileA, 0); to(.flare, 0)
        to(.blush, p.blush); to(.smile, state == .done ? 1 : 0)
        if state != .done { to(.lotus, 0) }
        to(.sleep, state == .resting ? 1 : 0)
    }

    private func doBlink() {
        to(.blink, 0.1)
        cancel(.bk)
        at(.bk, 0.09) { $0.to(.blink, 1) }
    }
    private func cheek() {
        to(.blush, 0.6)
        at(.ev, 0.8) { $0.to(.blush, RicePose.of($0.state).blush) }
    }
    private func press(_ amp: Double) {
        to(.sqx, 1 + 0.045 * amp); to(.sqy, max(0.9, 1 - 0.065 * amp)); to(.blink, 0.55)
    }
    private func release(_ amp: Double) {
        to(.sqx, 1); to(.sqy, 1); to(.blink, 1); kick(.sqy, 1.3 * amp); kick(.sqx, -1 * amp)
    }
    private func bored(_ on: Bool) {
        isBored = on
        if on { to(.lookY, 0.8); to(.tilt, -3); to(.boost, -0.35) } else { to(.lookY, 0); to(.tilt, 0); to(.boost, 0) }
    }
    /// Any sign of the user resets the bored timer.
    func touch() {
        idleSince = t
        if isBored { bored(false) }
    }
    private func ampFor(_ n: Int) -> Double {
        settings.spamBuildsUp ? min(1 + 0.15 * Double(n - 1), 1.45) : 1
    }

    // MARK: events (all interruptible; with Reduce Motion they are skipped)

    /// A1: first expansion after launch. Grows from small with eyes shut, light comes up, eyes open.
    func wake() {
        guard !reduced else { return }
        touch(); resetEv()
        to(.scale, 0.72); to(.sleep, 1); to(.dim, 0.5)
        ch[Ch.scale.rawValue].snap(); ch[Ch.sleep.rawValue].snap(); ch[Ch.dim.rawValue].snap()
        at(.ev, 0.2) { m in m.to(.scale, 1); m.to(.dim, 0); m.kick(.flare, 2.5); m.ripple(dur: 2, str: 0.7, size: 0.55) }
        at(.ev, 0.55) { $0.to(.sleep, $0.state == .resting ? 1 : 0) }
        at(.ev, 0.95) { $0.doBlink() }
    }

    /// First expansion after launch: wake up, then the wai greeting.
    func wakeAndGreet() {
        guard !reduced else { return }
        wake()
        at(.ev, 1.2) { $0.wai(.ev) }
    }

    /// A2: the notch opens again. A small grow from where it is, a settle, a blink.
    func opened() {
        guard !reduced else { return }
        touch()
        to(.scale, 0.88); ch[Ch.scale.rawValue].snap()
        at(.ev, 0.03) { m in m.to(.scale, 1); m.kick(.sqy, 0.9); m.kick(.sqx, -0.6) }
        at(.ev, 0.3) { $0.doBlink() }
    }

    /// X1: the notch folds. A soft squash and a blink as Seed settles into the strip.
    func folded() {
        guard !reduced else { return }
        to(.lookX, 0); to(.lookY, 0)
        kick(.sqy, -0.8); kick(.sqx, 0.6); doBlink()
    }

    /// A3: the wai greeting on its own.
    func greet() {
        guard !reduced else { return }
        wai(.ev)
    }

    /// E4: section switch. The eyes glance toward the rail below, then come back.
    func glanceToRail() {
        guard !reduced else { return }
        touch()
        to(.lookX, -0.4); to(.lookY, 1.4)
        at(.ev, 0.5) { m in m.to(.lookX, 0); m.to(.lookY, 0) }
    }

    /// The Action Ring blooms: a small lift, brighter light and a pass of the rim.
    func ringOpen() {
        guard !reduced else { return }
        touch()
        kick(.hop, -60); kick(.sqy, 0.9); kick(.sqx, -0.6); to(.boost, 0.3)
        rimPass(dur: 0.9, str: 0.6)
        at(.ev, 0.5) { $0.to(.boost, 0.12) }
    }

    /// The ring closes without a pick.
    func ringClose() {
        guard !reduced else { return }
        to(.boost, 0); to(.lookX, 0); to(.lookY, 0)
    }

    /// An action was picked: a nod and a gold ripple, then calm.
    func ringPick() {
        touch()
        to(.boost, 0); to(.lookX, 0); to(.lookY, 0)
        guard !reduced else { return }
        kick(.bow, 1.2); kick(.scale, 0.9)
        ripple(dur: 1.0, str: 0.55, size: 0.35, col: .gold)
        at(.ev, 0.12) { $0.doBlink() }
    }

    /// The user did something elsewhere in the notch: a quick look that way, then back.
    func notice(dx: Double, dy: Double) {
        guard !reduced else { return }
        touch()
        lookAt(dx: dx, dy: dy); kick(.scale, 0.35)
        at(.ev, 0.65) { m in m.to(.lookX, 0); m.to(.lookY, 0) }
    }

    /// Looks toward an Action Ring slot (dx, dy in points from Seed's centre).
    func lookAt(dx: Double, dy: Double) {
        guard !reduced else { return }
        let d = max(1, hypot(dx, dy))
        to(.lookX, dx / d * 1.4); to(.lookY, dy / d * 1.1)
    }

    /// A message between agents arrived or was picked: a quick look toward the
    /// timeline (right and a little down), a blink, then back.
    func glanceAtTimeline() {
        guard !reduced else { return }
        touch()
        to(.lookX, 1.2); to(.lookY, 0.6); kick(.scale, 0.6)
        at(.ev, 0.25) { $0.doBlink() }
        at(.ev, 0.8) { m in m.to(.lookX, 0); m.to(.lookY, 0) }
    }

    /// E3: Copy succeeded. A white grain-shaped outline spreads like a copy.
    func copied() {
        guard !reduced else { return }
        touch()
        ripple(dur: 1.15, str: 0.75, size: 0.4, col: .white)
        kick(.scale, 1.4); doBlink(); cheek()
    }

    /// E5: a new held request. Startle (eyes widen, tiptoe), then the approval posture.
    func newApproval() {
        touch()
        guard !reduced else { select(.approval); return }
        to(.boost, 0.2); to(.tip, 1); kick(.sqy, 1.2); kick(.sqx, -0.9); to(.lookX, 1.3); to(.lookY, -0.5)
        at(.ev, 0.18) { m in
            m.select(.approval, replay: true)
            m.ripple(dur: 2, str: 0.6, size: 0.5, col: .amber)
        }
        at(.ev, 0.4) { $0.to(.tip, 0) }
        at(.ev, 0.95) { m in m.to(.lookX, 0); m.to(.lookY, 0); m.to(.boost, 0) }
    }

    /// P5: a file is dragged over the notch. Anticipation toward the file.
    func startHover() {
        guard !reduced else { return }
        touch(); cancel(.hover); cancel(.ev)
        file = FileMotion(kind: .hover, t0: t, fx: 0, fy: 0, frot: 0)
        to(.fileA, 1); to(.recv, 1); to(.stretch, 1); to(.boost, 0.15)
        to(.lookX, 1.6); to(.lookY, -1.5); to(.tilt, 6); to(.lean, 1.5)
        ripple(dur: 1.1, str: 0.45, size: 0.55, inward: true)
    }
    func endHover() {
        cancel(.hover)
        guard file?.kind == .hover else { return }
        to(.fileA, 0); to(.recv, 0); to(.stretch, 0); to(.boost, 0)
        to(.lookX, 0); to(.lookY, 0); to(.tilt, 0); to(.lean, 0)
    }
    /// The drag left without a drop. Waits a moment so a drop arriving in the
    /// same update can take over the tile instead of it vanishing.
    func scheduleEndHover(after delay: Double = 0.15) {
        guard file?.kind == .hover else { return }
        cancel(.hover)
        at(.hover, delay) { $0.endHover() }
    }

    func fileNow() -> FileTile? {
        guard let f = file else { return nil }
        let tau = t - f.t0, r = reduced, m: Double = r ? 0 : 1
        let bx = lastX * 3 / 1.4, by = lastY * 3 / 1.4
        switch f.kind {
        case .hover:
            return FileTile(x: 72 + sin(tau * 1.6) * 2.5 * m, y: -96 + sin(tau * 2.1) * 3 * m,
                            rot: sin(tau * 1.3) * 4 * m, s: 1, o: 1)
        case .drop:
            let k = r ? (tau < 0.42 ? 0 : 1) : Self.clamp01(tau / 0.42), e = Self.inOut(k)
            return FileTile(x: f.fx + (bx - f.fx) * e, y: f.fy + (by - 8 - f.fy) * e,
                            rot: f.frot * (1 - e), s: 1 - 0.6 * e, o: k < 0.8 ? 1 : (1 - k) / 0.2)
        case .reject:
            let cx = bx + 48, cy = by - 74
            if tau < 0.36 {
                let e = r ? 0 : Self.inOut(tau / 0.36)
                return FileTile(x: f.fx + (cx - f.fx) * e, y: f.fy + (cy - f.fy) * e, rot: f.frot * (1 - e), s: 1, o: 1)
            }
            let k = r ? (tau < 0.9 ? 0 : 1) : Self.clamp01((tau - 0.36) / 0.7), e = Self.outC(k)
            return FileTile(x: cx + 44 * e, y: cy - 10 * e, rot: 8 * e, s: 1 - 0.1 * e, o: 1 - k)
        }
    }

    /// E1: a file was added to the shelf. It glides in, the grain gulps and puffs back, happy.
    func dropIn() {
        touch(); cancel(.hover)
        guard !reduced else { file = nil; return }
        cancel(.ev)
        let f = fileNow()
        file = FileMotion(kind: .drop, t0: t, fx: f?.x ?? 70, fy: f?.y ?? -96, frot: f?.rot ?? 0)
        to(.fileA, 1)
        to(.recv, 0); to(.stretch, 0.5); to(.lookX, 0.9); to(.lookY, -1); to(.tilt, 3); to(.boost, 0.1)
        at(.ev, 0.42) { m in
            m.to(.stretch, 0); m.to(.tilt, 0); m.to(.lean, 0); m.to(.sqx, 1.08); m.to(.sqy, 0.9)
            m.to(.lookX, 0); m.to(.lookY, 0); m.to(.blink, 0.25); m.to(.fileA, 0); m.kick(.flare, 2.5)
        }
        at(.ev, 0.68) { m in
            m.to(.sqx, 1); m.to(.sqy, 1); m.kick(.sqy, 1.8); m.kick(.sqx, -1.3); m.to(.blink, 1); m.to(.boost, 0)
            m.to(.smile, 1); m.cheek(); m.ripple(dur: 1.7, str: 0.65, size: 0.5)
        }
        at(.ev, 1.8) { m in if m.state != .done { m.to(.smile, 0) } }
    }

    /// E2: shelf full or file rejected. The file bumps the edge and drifts away; a polite "no".
    func reject() {
        touch(); cancel(.hover)
        guard !reduced else { file = nil; return }
        cancel(.ev)
        let f = fileNow()
        let useF = (f?.o ?? 0) > 0.5
        file = FileMotion(kind: .reject, t0: t, fx: useF ? f!.x : 96, fy: useF ? f!.y : -104, frot: f?.rot ?? 0)
        to(.fileA, 1)
        to(.recv, 0); to(.stretch, 0); to(.tilt, 0); to(.lean, 0); to(.lookX, 1.4); to(.lookY, -1.2)
        at(.ev, 0.36) { m in
            m.to(.lean, -1.2); m.to(.tilt, -4); m.to(.blink, 0.2); m.to(.dim, 0.35); m.kick(.sqx, 0.8); m.kick(.sqy, -1)
        }
        at(.ev, 0.6) { m in
            m.to(.tilt, 0); m.to(.lean, 0); m.to(.blink, 0.6); m.to(.lookX, 0); m.to(.lookY, 0.5); m.to(.shakeA, 5)
        }
        at(.ev, 0.9) { $0.to(.shakeA, -5) }
        at(.ev, 1.2) { $0.to(.shakeA, 3) }
        at(.ev, 1.45) { $0.to(.shakeA, 0) }
        at(.ev, 1.6) { $0.to(.bow, 0.4) }
        at(.ev, 2.25) { m in m.to(.bow, 0); m.to(.blink, 1); m.to(.dim, 0); m.to(.lookY, 0); m.to(.fileA, 0) }
    }

    // MARK: pointer

    /// P1-P3: gaze follows the pointer. `dx`, `dy` are the pointer offset from the
    /// mascot centre, `range` the distance that counts as "far", `vx` the smoothed
    /// horizontal pointer velocity, `nearRadius` the distance that counts as "close".
    func pointer(dx: Double, dy: Double, range: Double, vx: Double, nearRadius: Double) {
        guard !reduced else { return }
        touch()
        let r = max(1, range)
        to(.curX, max(-3, min(3, dx / r * 4.8)))
        to(.curY, max(-2, min(2, dy / r * 3.2)))
        guard file == nil else { return }
        to(.tilt, max(-2.5, min(2.5, vx * 0.15)))
        let near = hypot(dx, dy) < nearRadius
        to(.lean, near ? max(-1.5, min(1.5, dx / nearRadius * 1.5)) : 0)
        to(.boost, near ? 0.08 : 0)
    }
    /// P4: the pointer left. Eyes settle back.
    func pointerLeft() {
        to(.curX, 0); to(.curY, 0)
        if file == nil { to(.lean, 0); to(.boost, 0); to(.tilt, 0) }
    }

    /// C1-C4: press squash. Clicks within 1.2 s build up (owner's choice).
    func pressDown() {
        guard !reduced else { return }
        touch()
        held = false
        clicks.removeAll { t - $0 >= 1.2 }
        clicks.append(t)
        press(ampFor(min(clicks.count, 4)))
        cancel(.hold)
        at(.hold, 0.4) { m in m.held = true; m.to(.sqy, 0.91); m.to(.blink, 0.08) }
    }
    func pressUp() {
        guard !reduced else { return }
        cancel(.hold)
        let n = min(clicks.count, 4)
        if held {
            release(1.5)
        } else {
            release(ampFor(max(1, n)))
            if n == 1 { doBlink(); cheek(); ripple(dur: 1.3, str: 0.45, size: 0.3) }
        }
        held = false
    }

    // MARK: Reduce Motion

    func setReduced(_ on: Bool) {
        guard on != reduced else { return }
        reduced = on
        cancel(.ev); cancel(.bk); cancel(.hold); cancel(.hover)
        file = nil
        if isBored { bored(false) }
        resetEv()
        select(state, replay: false)
        if on { snapAll(); clearLight() }
    }

    private func snapAll() {
        for i in ch.indices { ch[i].snap() }
        for i in w.indices { w[i].snap(); pr[i].snap() }
    }
    private func clearLight() {
        ripples.removeAll(); motes.removeAll(); zs.removeAll(); rim = nil; trail = nil
    }

    private var lastClock: Double?
    /// Advances to a wall-clock time from the TimelineView. A long gap (the
    /// view was paused or hidden) resumes with one ordinary frame, never a jump.
    func advance(to clock: Double) {
        defer { lastClock = clock }
        guard let last = lastClock else { step(0); return }
        let dt = clock - last
        step(dt > 0.25 || dt < 0 ? 1.0 / 60.0 : dt)
    }

    /// How fast Seed needs frames right now. A frame costs the same whatever it
    /// shows, so the rate follows what is on screen: quick springs (a press, a
    /// hop, a glance) get 60 fps; slow light (a rim pass, motes, ripples, the
    /// working arc) and springs in their last slow ease get 30; the idle breath
    /// and float move under a fifth of a point per frame at 12 fps.
    enum Pace: Sendable { case full, light, breath }

    var pace: Pace {
        if file != nil || nextTaskTime - t < 0.1 { return .full }
        if ch.contains(where: { !$0.isCalm }) || w.contains(where: { !$0.isCalm }) || pr.contains(where: { !$0.isCalm }) { return .full }
        if ch.contains(where: { !$0.isSettled }) || w.contains(where: { !$0.isSettled }) || pr.contains(where: { !$0.isSettled }) { return .light }
        if state == .working || state == .sending { return .light }
        if !ripples.isEmpty || rim != nil || !motes.isEmpty || !zs.isEmpty || trail != nil { return .light }
        return .breath
    }

    /// Seconds between frames for the current pace.
    var frameInterval: Double {
        switch pace {
        case .full:   return 1.0 / 60.0
        case .light:  return 1.0 / 30.0
        case .breath: return 1.0 / 12.0
        }
    }

    /// True while the TimelineView must keep drawing. With Reduce Motion the
    /// mascot holds one snapped posture, so nothing needs frames.
    var needsFrames: Bool { !paused && !reduced }

    // MARK: per frame

    func step(_ dtIn: Double) {
        guard !paused else { return }
        let dt = min(max(dtIn, 0), 0.05)
        t += dt
        if nextTaskTime <= t {
            var due: [Task] = []
            tasks.removeAll { task in
                if task.t <= t { due.append(task); return true }
                return false
            }
            nextTaskTime = tasks.reduce(Double.infinity) { min($0, $1.t) }
            due.sort { $0.t < $1.t }
            for task in due { task.fn(self) }
        }
        if reduced {
            snapAll()
            clearLight()
        } else {
            for i in ch.indices { ch[i].step(dt) }
            for i in w.indices { w[i].step(dt); pr[i].step(dt) }
            ripples.removeAll { t - $0.t0 >= $0.dur }
            motes.removeAll { t - $0.t0 >= $0.life }
            zs.removeAll { t - $0.t0 >= $0.dur }
            if let r = rim, t - r.t0 >= r.dur { rim = nil }
            if let tr = trail, t - tr.t0 >= tr.dur { trail = nil }
            if t >= nextBlink && state != .resting && state != .done {
                doBlink()
                if chance(1.0 / 6.0) { at(.bk, 0.25) { $0.doBlink() } }
                nextBlink = t + rand(3, 6)
            }
            if settings.boredPose && state == .idle && !isBored && t - idleSince > 25 { bored(true) }
        }
        if let f = file, f.kind != .hover, v(.fileA) < 0.01, t - f.t0 > 0.5 { file = nil }
    }

    func values() -> RiceFrame {
        let r = reduced, M: Double = r ? 0 : 1
        let wIdle = weight(.idle); _ = wIdle
        let wThinking = weight(.thinking), wWorking = weight(.working), wSending = weight(.sending)
        let wApproval = weight(.approval), wResting = weight(.resting)
        var x = 0.0, y = 0.0, a = 0.0, sx = 1.0, sy = 1.0, lx = 0.0, ly = 0.0, glow = 0.0, follow = 1.0
        let awake = 1 - wResting
        // Shared life: a very slow breath and float, almost still.
        let br = sin(t * 1.37) * M * awake
        y += sin(t * 1.0) * 0.9 * M * awake * (1 - 0.6 * wWorking)
        sx *= 1 - 0.008 * br; sy *= 1 + 0.012 * br
        // Posture-level gaze per intent (kept with Reduce Motion).
        lx += -2.2 * wThinking + 1.1 * wSending
        ly += -2 * wThinking + 0.9 * wWorking
        follow -= 0.6 * wThinking + 0.6 * wWorking + 0.3 * wSending + 0.85 * wApproval + 1 * wResting
        // Resting: deep slow breath.
        let rb = sin(t * 1.25) * M * wResting
        sy *= 1 + 0.03 * rb; sx *= 1 - 0.018 * rb; glow += 0.06 * rb
        // Phrase channels.
        let hm = v(.hmm); a -= 4 * hm; y -= hm; ly -= 0.4 * hm
        let d = v(.dip); a += 2.5 * d; y += 1.2 * d; sy *= 1 - 0.035 * d; sx *= 1 + 0.025 * d
        let s = v(.send), tr = settings.sendLean
        if s < 0 { a += 6 * s; sy *= 1 + 0.04 * s; sx *= 1 - 0.03 * s; x += 2 * s }
        else { a += 8 * s; sy *= 1 + 0.05 * s; sx *= 1 - 0.035 * s; x += tr * s }
        let tp = v(.tip); y -= 3 * tp; sy *= 1 + 0.04 * tp; sx *= 1 - 0.025 * tp
        // Events.
        let bw = v(.bow), st = v(.stretch)
        x += v(.poseX) + v(.lean)
        y += v(.poseY) + v(.hop) + bw * 7 - st * 2.5
        a += v(.poseAngle) + v(.tilt) + v(.shakeA)
        sx *= v(.poseSX) * v(.sqx) * v(.scale) * (1 + 0.03 * bw) * (1 - 0.035 * st)
        sy *= v(.poseSY) * v(.sqy) * v(.scale) * (1 - 0.06 * bw) * (1 + 0.05 * st)
        ly += 1.3 * bw
        let gx = settings.gazeX, gy = settings.gazeY
        follow = max(0, follow)
        var ex = (v(.curX) * follow + v(.lookX) + lx) * gx / 3
        var ey = (v(.curY) * follow + v(.lookY) + ly) * gy / 2
        let ar = -a * .pi / 180, cs = cos(ar), sn = sin(ar)
        (ex, ey) = (ex * cs - ey * sn, ex * sn + ey * cs)
        if ey < 0 { ey *= 1.7 }                              // more room above the eyes than below
        let gyv = ey < 0 ? gy * 1.7 : gy
        let n = hypot(ex / gx, ey / gyv)
        if n > 1 { ex /= n; ey /= n }                        // eyes can never leave the body
        let eyeOpen = min(1.3, max(0.06, v(.poseEye) * (1 + v(.boost)) * min(v(.blink), 1)))
        glow = max(0, v(.poseGlow) + glow + v(.flare) - v(.dim) + 0.2 * v(.recv))
        lastX = x; lastY = y
        return RiceFrame(x: x, y: y, angle: a, sx: sx, sy: sy, ex: ex, ey: ey, eyeOpen: eyeOpen, glow: glow,
                         blush: v(.blush), smile: Self.clamp01(v(.smile)), sleep: Self.clamp01(v(.sleep)),
                         t: t, reduced: r, resting: wResting)
    }

    // MARK: easing

    static func clamp01(_ x: Double) -> Double { max(0, min(1, x)) }
    static func inOut(_ k0: Double) -> Double {
        let k = clamp01(k0)
        return k < 0.5 ? 4 * k * k * k : 1 - pow(-2 * k + 2, 3) / 2
    }
    static func outC(_ k: Double) -> Double { 1 - pow(1 - clamp01(k), 3) }
    static func bump(_ k: Double) -> Double { (k <= 0 || k >= 1) ? 0 : sin(.pi * k) }
}
#endif
