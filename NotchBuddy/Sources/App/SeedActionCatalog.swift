import Foundation
import CoreGraphics

// MARK: - Seed's Action Ring: catalog, the user's choice and geometry (pure)
//
// Tap Seed and up to six actions bloom around it, one per direction (like an
// MX Master Actions Ring). Point or flick toward one to pick it. The user
// chooses which actions sit in the ring. Only Seed's own features: nothing
// that copies a macOS feature such as screenshots.

enum SeedAction: String, CaseIterable, Codable, Sendable {
    case agents, timeline, review, mcp
    case shelf, folders, clipboard, usage
    case refresh, manager, sound, settings

    var title: String {
        switch self {
        case .agents:    return "Agents"
        case .timeline:  return "Timeline"
        case .review:    return "Review"
        case .mcp:       return "MCP"
        case .shelf:     return "Shelf"
        case .folders:   return "Folders"
        case .clipboard: return "Clipboard"
        case .usage:     return "Usage"
        case .refresh:   return "Refresh agents"
        case .manager:   return "Open Manager"
        case .sound:     return "Sounds on/off"
        case .settings:  return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .agents:    return "person.2.fill"
        case .timeline:  return "point.3.connected.trianglepath.dotted"
        case .review:    return "hand.raised.fill"
        case .mcp:       return "server.rack"
        case .shelf:     return "tray.full.fill"
        case .folders:   return "folder.fill"
        case .clipboard: return "doc.on.clipboard.fill"
        case .usage:     return "chart.bar.fill"
        case .refresh:   return "arrow.clockwise"
        case .manager:   return "slider.horizontal.3"
        case .sound:     return "speaker.wave.2.fill"
        case .settings:  return "gearshape.fill"
        }
    }
}

/// The user's ring: which actions, in which order (first = nearest the top).
/// Kept in UserDefaults for now; plan 005 lets the user's agent edit it too.
@MainActor
final class SeedRingStore: ObservableObject {
    static let shared = SeedRingStore()
    static let capacity = 6
    static let defaults: [SeedAction] = [.timeline, .review, .shelf, .clipboard, .usage, .settings]
    private static let key = "seed.ring.slots"

    @Published private(set) var slots: [SeedAction]
    private let store: UserDefaults

    init(store: UserDefaults = .standard) {
        self.store = store
        slots = Self.decode(store.stringArray(forKey: Self.key))
    }

    /// Unknown ids are dropped, duplicates removed, at most `capacity` kept;
    /// an empty or missing list falls back to the defaults.
    static func decode(_ raw: [String]?) -> [SeedAction] {
        var seen = Set<SeedAction>()
        let list = (raw ?? []).compactMap(SeedAction.init(rawValue:)).filter { seen.insert($0).inserted }
        return list.isEmpty ? defaults : Array(list.prefix(capacity))
    }

    /// Adds the action at the end, or removes it if it is already in the ring.
    /// A full ring ignores additions; the last action cannot be removed.
    func toggle(_ action: SeedAction) {
        if let i = slots.firstIndex(of: action) {
            guard slots.count > 1 else { return }
            slots.remove(at: i)
        } else {
            guard slots.count < Self.capacity else { return }
            slots.append(action)
        }
        save()
    }

    /// Picks up a change made outside the app, e.g. by the user's agent with
    /// `defaults write com.grunte.seed seed.ring.slots -array …`.
    func reload() {
        let fresh = Self.decode(store.stringArray(forKey: Self.key))
        if fresh != slots { slots = fresh }
    }

    /// Moves a ring action one place earlier (-1) or later (+1); out of range is ignored.
    func move(_ action: SeedAction, by step: Int) {
        guard let i = slots.firstIndex(of: action), slots.indices.contains(i + step) else { return }
        slots.swapAt(i, i + step)
        save()
    }

    func reset() {
        slots = Self.defaults
        save()
    }

    private func save() { store.set(slots.map(\.rawValue), forKey: Self.key) }
}

/// Where the slots sit around Seed. Seed lives in the notch's top-left corner,
/// so the ring is a fan that opens right and down, never past the notch edge.
enum SeedRingGeometry {
    static let radius: CGFloat = 104
    /// Fan from slightly above right (-12°) to slightly left of down (102°); y points down.
    static let start: Double = -12
    static let end: Double = 102
    /// Below this distance from Seed's centre nothing is pointed at.
    static let deadZone: CGFloat = 16

    static func angles(count: Int) -> [Double] {
        guard count > 0 else { return [] }
        guard count > 1 else { return [(start + end) / 2] }
        let step = (end - start) / Double(count - 1)
        return (0..<count).map { start + Double($0) * step }
    }

    static func offset(index: Int, count: Int, radius: CGFloat = radius) -> CGSize {
        let a = angles(count: count)[index] * .pi / 180
        return CGSize(width: radius * CGFloat(cos(a)), height: radius * CGFloat(sin(a)))
    }

    /// The slot pointed at by a vector from Seed's centre, nearest by angle.
    /// 30° of leeway past the fan's ends; nil inside the dead zone or far off the fan.
    static func slot(for vector: CGSize, count: Int) -> Int? {
        guard count > 0, hypot(vector.width, vector.height) >= deadZone else { return nil }
        var deg = atan2(Double(vector.height), Double(vector.width)) * 180 / .pi
        if deg < -90 { deg += 360 }   // keep up-left on the far side of the fan, never wrap to its start
        let list = angles(count: count)
        guard deg >= start - 30, deg <= end + 30 else { return nil }
        return list.indices.min { abs(list[$0] - deg) < abs(list[$1] - deg) }
    }
}
