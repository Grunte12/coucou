import Foundation
import CoreGraphics

@main
struct SeedActionRingTests {
    static var failures = 0
    static func check(_ ok: Bool, _ name: String) {
        if !ok { failures += 1; print("FAIL: \(name)") }
    }
    static func vector(degrees: Double, length: CGFloat = 80) -> CGSize {
        let a = degrees * .pi / 180
        return CGSize(width: length * CGFloat(cos(a)), height: length * CGFloat(sin(a)))
    }

    @MainActor static func main() {
        // Geometry: a fan that opens right and down from Seed in the top-left corner.
        let six = SeedRingGeometry.angles(count: 6)
        check(six.count == 6 && six.first == SeedRingGeometry.start && six.last == SeedRingGeometry.end, "six slots span the whole fan")
        check(SeedRingGeometry.angles(count: 1) == [(SeedRingGeometry.start + SeedRingGeometry.end) / 2], "a single slot sits mid-fan")
        check(SeedRingGeometry.angles(count: 0).isEmpty, "no slots, no angles")
        // Neighbouring 34 pt slots never touch.
        let a = SeedRingGeometry.offset(index: 0, count: 6), b = SeedRingGeometry.offset(index: 1, count: 6)
        check(hypot(a.width - b.width, a.height - b.height) >= 38, "slots keep a gap between them")
        // Seed's centre is 44,42 in the pane: every 34 pt slot stays inside the pane.
        for i in 0..<6 {
            let o = SeedRingGeometry.offset(index: i, count: 6)
            check(44 + o.width - 17 >= 0 && 42 + o.height - 17 >= 0, "slot \(i) stays inside the notch")
        }

        // Pointing: nearest slot by angle, a dead zone on Seed, nothing far off the fan.
        for (i, deg) in six.enumerated() {
            check(SeedRingGeometry.slot(for: vector(degrees: deg), count: 6) == i, "pointing at slot \(i) picks it")
        }
        check(SeedRingGeometry.slot(for: CGSize(width: 6, height: 6), count: 6) == nil, "inside the dead zone nothing is picked")
        check(SeedRingGeometry.slot(for: vector(degrees: -10), count: 6) == 0, "just above the first slot still picks it")
        check(SeedRingGeometry.slot(for: vector(degrees: -135), count: 6) == nil, "up-left (off the notch) picks nothing")
        check(SeedRingGeometry.slot(for: vector(degrees: 180), count: 6) == nil, "straight left picks nothing")
        check(SeedRingGeometry.slot(for: vector(degrees: 45), count: 0) == nil, "an empty ring picks nothing")
        check(SeedRingGeometry.slot(for: vector(degrees: 170), count: 1) == nil, "a lone slot ignores the far side")

        // The user's choice: decoding is forgiving and bounded.
        check(SeedRingStore.decode(nil) == SeedRingStore.defaults, "missing list falls back to defaults")
        check(SeedRingStore.decode(["nope"]) == SeedRingStore.defaults, "unknown ids only: defaults")
        check(SeedRingStore.decode(["usage", "usage", "shelf"]) == [.usage, .shelf], "duplicates removed, order kept")
        check(SeedRingStore.decode(SeedAction.allCases.map(\.rawValue)).count == SeedRingStore.capacity, "never more than six")
        check(!SeedAction.allCases.contains { $0.rawValue.contains("screen") }, "no copies of macOS features such as screenshots")

        // Toggle, capacity, last-slot guard, persistence and reset.
        let suite = "seed.ring.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SeedRingStore(store: defaults)
        check(store.slots == SeedRingStore.defaults, "fresh store starts with defaults")
        store.toggle(.agents)
        check(!store.slots.contains(.agents), "a full ring ignores additions")
        store.toggle(.settings)
        store.toggle(.agents)
        check(store.slots.last == .agents && !store.slots.contains(.settings), "remove then add appends at the end")
        check(SeedRingStore(store: defaults).slots == store.slots, "the choice survives a relaunch")
        for action in store.slots.dropFirst() { store.toggle(action) }
        store.toggle(store.slots[0])
        check(store.slots.count == 1, "the last action cannot be removed")
        store.reset()
        check(store.slots == SeedRingStore.defaults && SeedRingStore(store: defaults).slots == SeedRingStore.defaults, "reset restores and saves defaults")

        if failures == 0 { print("SeedActionRingTests: all passed") } else { exit(1) }
    }
}
