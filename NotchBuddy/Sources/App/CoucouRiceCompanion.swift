#if COUCOU_HUB
import SwiftUI

extension Notification.Name {
    /// Posted by the Clipboard pane after a successful Copy.
    static let coucouRiceCopied = Notification.Name("coucouRiceCopied")
    /// Seed's wai greeting (the user came back after a while).
    static let seedGreet = Notification.Name("seedGreet")
    /// Posted when the shelf rejects a drop (full, not a local file, ...).
    static let coucouShelfRejected = Notification.Name("coucouShelfRejected")
}

/// Keeps one RiceMotion per workspace without re-creating it on every parent
/// render. Nothing here is published, so motion never re-renders SwiftUI.
@MainActor
final class RiceMotionHolder: ObservableObject {
    /// Seed is one character: the notch strip, every view and the workspace share
    /// this motion, so a pose carries over when the notch opens or closes.
    static let shared = RiceMotionHolder()
    let motion = RiceMotion()
    var lastPointerX: Double?
    var pointerVX = 0.0
    /// The wake-up and wai greeting play once per launch.
    static var greetedThisLaunch = false
    /// A short "done" moment after something finished, shared by every Seed view.
    @Published private(set) var celebrating = false
    private var celebration = 0

    func celebrate(for seconds: Double = 2.6) {
        celebration &+= 1
        let mine = celebration
        celebrating = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, self.celebration == mine else { return }
            self.celebrating = false
        }
    }

    /// Pointer in the workspace's own coordinates; `centre` is the mascot's centre there.
    func pointer(_ location: CGPoint?, centre: CGPoint) {
        guard let location else {
            motion.pointerLeft(); lastPointerX = nil; pointerVX = 0
            return
        }
        if let last = lastPointerX { pointerVX = pointerVX * 0.6 + (location.x - last) * 0.4 }
        lastPointerX = location.x
        motion.pointer(dx: location.x - centre.x, dy: location.y - centre.y,
                       range: 160, vx: pointerVX, nearRadius: 30)
    }
}

/// Lab-only: SEED_LAB_FREEZE_RICE=1 holds the mascot still, to measure the rest of the pane.
enum SeedLabSwitch {
    #if COUCOU_LAB
    static let freezeRice = ProcessInfo.processInfo.environment["SEED_LAB_FREEZE_RICE"] == "1"
    #else
    static let freezeRice = false
    #endif
}

/// The rice mascot in the workspace gutter. It only reflects real data and never
/// decides or approves anything: pressing it just squashes it.
struct CoucouRiceCompanion: View {
    @ObservedObject var holder: RiceMotionHolder
    @ObservedObject var state: AppState
    /// The workspace section, so Seed glances at the rail on a switch (nil outside the workspace).
    var section: CoucouWorkspaceSection? = nil
    /// Lab-size of the grain and the square it draws in (aura included).
    var box: CGFloat = 52
    var side: CGFloat = 84
    /// Tap on Seed (a press that is not a hold). Nil: presses only squash.
    var onTap: (() -> Void)? = nil
    /// Press Seed and drag: the translation so far, and whether the press ended.
    /// Lets the Action Ring be opened and picked in one flick.
    var onFlick: ((CGSize, Bool) -> Void)? = nil
    /// Only one Seed view drives events: the strip's copy stays quiet while the
    /// workspace draws its own, or every reaction would play twice. A quiet copy
    /// is hidden, so it also stops drawing frames.
    var reacts: Bool = true

    @ObservedObject private var model = CoucouHubIntegration.shared.model
    @ObservedObject private var shelf = CoucouHubIntegration.shared.workspace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revision = 0
    @State private var heldBaseline: Set<String>?
    @State private var pressing = false
    @State private var pressedAt = Date.distantPast

    private var motion: RiceMotion { holder.motion }

    private var heldIDs: Set<String> { Set(model.tincanInbox?.held.map(\.requestID) ?? []) }
    /// A terminal agent (through its hook) is waiting on the user.
    private var hookWaiting: Bool { state.pendingApproval != nil || state.pendingQuestion != nil }
    private var anyAgentWorking: Bool {
        (model.tincanRoster?.agents.contains { $0.claimed > 0 } ?? false)
            || state.tasks.contains { [.working, .thinking, .searching].contains($0.state) }
    }
    private var isOffline: Bool { model.connection == .offline || model.connection == .unpaired }

    /// Mood from real data only. "Done" is a short moment after something finished.
    private var mood: RiceState {
        if model.heldRequestCount > 0 || hookWaiting { return .approval }
        if holder.celebrating { return .done }
        if anyAgentWorking { return .working }
        if isOffline { return .resting }
        return .idle
    }

    private var statusText: String {
        let held = model.heldRequestCount + (hookWaiting ? 1 : 0)
        switch mood {
        case .approval: return held == 1 ? "1 request waiting for you" : "\(held) requests waiting for you"
        case .done:     return "Done"
        case .working:  return "An agent is working"
        case .resting:  return model.connection == .unpaired ? "Not paired" : "Offline"
        default:        return "Ready"
        }
    }

    var body: some View {
        // Split in two so the type checker keeps up: the mascot and its own
        // lifecycle, then the data it reacts to.
        reactions(mascot)
    }

    private var mascot: some View {
        let k = side / 84
        return RiceMascotView(motion: motion, box: box, paused: !reacts || state.mode == .hidden || SeedLabSwitch.freezeRice, revision: revision)
            .frame(width: side, height: side)
            // Only the grain itself takes presses, so the rail below stays clickable.
            .contentShape(Ellipse().size(width: 30 * k, height: 42 * k).offset(x: 27 * k, y: 20 * k))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !pressing {
                            pressing = true; pressedAt = Date()
                            motion.pressDown(); bump()
                        }
                        if hypot(value.translation.width, value.translation.height) >= 6 {
                            onFlick?(value.translation, false)
                        }
                    }
                    .onEnded { value in
                        pressing = false
                        motion.pressUp(); bump()
                        let quick = Date().timeIntervalSince(pressedAt) < 0.4
                        let still = hypot(value.translation.width, value.translation.height) < 6
                        if still { if quick { onTap?() } } else { onFlick?(value.translation, true) }
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(CoucouBrand.name)
            .accessibilityValue(statusText)
            .onAppear {
                heldBaseline = model.tincanInbox == nil ? nil : heldIDs
                guard reacts else { return }
                motion.setReduced(reduceMotion)
                motion.select(mood)
                if !RiceMotionHolder.greetedThisLaunch {
                    RiceMotionHolder.greetedThisLaunch = true
                    motion.wakeAndGreet()
                } else if section != nil {
                    // The workspace opened again: its Seed takes over with a small pop.
                    motion.opened()
                }
                bump()
            }
            .onChange(of: state.mode) { old, new in
                guard reacts else { return }
                if new == .expanded && old != .expanded { motion.opened() }
                if new != .expanded && old == .expanded { motion.folded() }
                bump()
            }
            .onChange(of: hookWaiting) { _, waiting in
                guard reacts, waiting else { return }
                motion.newApproval(); bump()
            }
            .onChange(of: state.pendingApproval?.sessionId) { old, new in
                // A terminal agent's request was answered.
                if old != nil && new == nil { celebrate() }
            }
            .onChange(of: state.view) { _, view in
                if view == .finished { celebrate() }
            }
    }

    private func reactions<V: View>(_ content: V) -> some View {
        content
            .onChange(of: reduceMotion) { _, on in
                guard reacts else { return }
                motion.setReduced(on); bump()
            }
            // Taking over from the other copy: catch up on the current mood.
            .onChange(of: reacts) { _, on in
                guard on else { return }
                motion.select(mood)
                if state.mode != .expanded { motion.folded() }
                bump()
            }
            .onChange(of: mood) { _, next in
                guard reacts else { return }
                motion.select(next); bump()
            }
            .onChange(of: heldIDs) { _, ids in
                // The first read is a baseline: history is never replayed as "new".
                // A quiet copy still tracks it, so it never replays on handover.
                guard let known = heldBaseline else { heldBaseline = ids; return }
                heldBaseline = ids
                let arrived = !ids.subtracting(known).isEmpty
                if !arrived && !known.subtracting(ids).isEmpty { celebrate() }
                guard reacts else { return }
                if arrived { motion.newApproval(); bump() }
            }
            .onChange(of: shelf.files.count) { old, new in
                guard reacts else { return }
                if new > old { motion.dropIn(); bump() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .coucouShelfRejected)) { _ in
                guard reacts else { return }
                motion.reject(); bump()
            }
            .onChange(of: state.fileDragOver) { _, over in
                guard reacts else { return }
                if over { motion.startHover() } else { motion.scheduleEndHover() }
                bump()
            }
            .onReceive(NotificationCenter.default.publisher(for: .seedGreet)) { _ in
                guard reacts else { return }
                motion.greet(); bump()
            }
            .onReceive(NotificationCenter.default.publisher(for: .coucouRiceCopied)) { _ in
                guard reacts else { return }
                motion.copied(); bump()
            }
            .onReceive(NotificationCenter.default.publisher(for: .seedNotice)) { note in
                guard reacts, let d = (note.object as? NSValue)?.sizeValue else { return }
                motion.notice(dx: d.width, dy: d.height); bump()
            }
            .onReceive(NotificationCenter.default.publisher(for: .seedGlance)) { _ in
                guard reacts else { return }
                motion.glanceAtTimeline(); bump()
            }
            .onChange(of: section) { _, next in
                guard reacts else { return }
                if next != nil { motion.glanceToRail(); bump() }
            }
    }

    /// Re-evaluates the view so a paused timeline (Reduce Motion) draws the new posture once.
    private func bump() { revision &+= 1 }

    /// Something finished or was answered: the done pose for a moment, then the real mood again.
    /// Either copy may start it: the holder is shared, a second call only restarts the moment.
    private func celebrate() {
        holder.celebrate()
    }
}
#endif
