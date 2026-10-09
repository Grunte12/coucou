import Foundation
import CoreGraphics

// MARK: - Agent timeline layout (pure)
//
// Swimlanes: one row per agent, time left→right, newest at the right edge.
// Each message is a curve from the sender's lane to the recipient's lane.
// Spacing is by order, not wall-clock time, so a quiet hour never leaves a
// gap wider than the notch. No SwiftUI here, so it is testable on its own.

enum SeedEdgeKind: Equatable, Sendable {
    /// Waiting for the user's decision.
    case held
    /// Claimed, queued, running or waiting for input.
    case open
    /// Answered or completed: drawn with a thin return curve.
    case answered
    /// Failed, denied or expired: red and dashed.
    case failed

    static func of(state: String, held: Bool) -> SeedEdgeKind {
        if held || state.lowercased() == "held" { return .held }
        switch state.lowercased() {
        case "replied", "answered", "complete", "completed", "succeeded", "success": return .answered
        case "denied", "declined", "failed", "error", "expired": return .failed
        default: return .open
        }
    }
}

struct SeedTimelineInput: Equatable, Sendable {
    let id: String
    let sender: String
    let recipient: String
    let state: String
    let held: Bool
    let date: Date?
}

struct SeedTimelineLayout: Equatable {
    struct Edge: Equatable, Identifiable {
        let id: String
        let from: Int
        let to: Int
        /// Start x; the curve ends at x + run.
        let x: CGFloat
        let kind: SeedEdgeKind
        let date: Date?
    }
    struct Tick: Equatable {
        let x: CGFloat
        let label: String
    }

    static let step: CGFloat = 72
    static let run: CGFloat = 42
    static let lead: CGFloat = 16
    /// Room after the newest curve for its return arc and the "now" mark.
    static let tail: CGFloat = 40

    let lanes: [String]
    let edges: [Edge]
    let ticks: [Tick]
    let width: CGFloat
    /// x of the "now" mark.
    let nowX: CGFloat

    /// Oldest first. Lanes keep the order in which agents first appear; the
    /// most recent `limit` messages are kept. Content is right-aligned when it
    /// is narrower than `minWidth`, so the newest work always sits next to "now".
    static func make(_ input: [SeedTimelineInput], minWidth: CGFloat, limit: Int = 60,
                     calendar: Calendar = .current) -> SeedTimelineLayout {
        let ordered = Array(input.enumerated()
            .sorted { a, b in
                let da = a.element.date ?? .distantPast, db = b.element.date ?? .distantPast
                return da == db ? a.offset > b.offset : da < db
            }
            .map(\.element)
            .suffix(limit))
        var lanes: [String] = []
        func lane(_ id: String) -> Int {
            if let i = lanes.firstIndex(of: id) { return i }
            lanes.append(id); return lanes.count - 1
        }
        let natural = ordered.isEmpty ? 0 : lead + CGFloat(ordered.count - 1) * step + run + tail
        let width = max(minWidth, natural)
        let shift = width - natural
        var edges: [Edge] = []
        var ticks: [Tick] = []
        let fmt = DateFormatter()
        fmt.calendar = calendar
        fmt.timeZone = calendar.timeZone
        fmt.dateFormat = "HH:mm"
        var lastLabel: String?
        var lastTickX = -CGFloat.infinity
        for (i, m) in ordered.enumerated() {
            let x = shift + lead + CGFloat(i) * step
            let from = lane(m.sender), to = lane(m.recipient)
            edges.append(Edge(id: m.id, from: from, to: to, x: x,
                              kind: .of(state: m.state, held: m.held), date: m.date))
            // A time label only when the minute changes and there is room for it.
            if let d = m.date {
                let label = fmt.string(from: d)
                if label != lastLabel && x - lastTickX >= 44 {
                    ticks.append(Tick(x: x, label: label))
                    lastLabel = label; lastTickX = x
                }
            }
        }
        return SeedTimelineLayout(lanes: lanes, edges: edges, ticks: ticks,
                                  width: width, nowX: width - 12)
    }

    // MARK: Geometry

    static func laneY(_ lane: Int, laneHeight: CGFloat, top: CGFloat = 0) -> CGFloat {
        top + (CGFloat(lane) + 0.5) * laneHeight
    }

    /// Cubic curve from the sender's lane to the recipient's lane.
    /// A message to oneself bulges upward instead.
    static func curve(_ e: Edge, laneHeight: CGFloat, top: CGFloat = 0)
        -> (CGPoint, CGPoint, CGPoint, CGPoint) {
        let y0 = laneY(e.from, laneHeight: laneHeight, top: top)
        let y1 = laneY(e.to, laneHeight: laneHeight, top: top)
        let p0 = CGPoint(x: e.x, y: y0), p3 = CGPoint(x: e.x + run, y: y1)
        if e.from == e.to {
            let lift = laneHeight * 0.45
            return (p0, CGPoint(x: e.x + run * 0.2, y: y0 - lift),
                    CGPoint(x: e.x + run * 0.8, y: y1 - lift), p3)
        }
        return (p0, CGPoint(x: e.x + run * 0.55, y: y0), CGPoint(x: e.x + run * 0.45, y: y1), p3)
    }

    static func point(on c: (CGPoint, CGPoint, CGPoint, CGPoint), t: CGFloat) -> CGPoint {
        let u = 1 - t
        let a = u * u * u, b = 3 * u * u * t, cc = 3 * u * t * t, d = t * t * t
        return CGPoint(x: a * c.0.x + b * c.1.x + cc * c.2.x + d * c.3.x,
                       y: a * c.0.y + b * c.1.y + cc * c.2.y + d * c.3.y)
    }

    /// The edge whose curve passes within `radius` of `p`, nearest first.
    func hit(_ p: CGPoint, laneHeight: CGFloat, top: CGFloat = 0, radius: CGFloat = 9) -> Edge? {
        var best: (Edge, CGFloat)?
        for e in edges where p.x >= e.x - radius && p.x <= e.x + Self.run + radius {
            let c = Self.curve(e, laneHeight: laneHeight, top: top)
            for i in 0...16 {
                let q = Self.point(on: c, t: CGFloat(i) / 16)
                let d = hypot(q.x - p.x, q.y - p.y)
                if d <= radius && d < (best?.1 ?? .infinity) { best = (e, d) }
            }
        }
        return best?.0
    }
}
