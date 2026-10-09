import Foundation
import CoreGraphics

@main
struct SeedTimelineLayoutTests {
    static var failures = 0
    static func check(_ ok: Bool, _ name: String) {
        if !ok { failures += 1; print("FAIL: \(name)") }
    }
    static func at(_ minute: Int) -> Date { Date(timeIntervalSince1970: 1_791_400_000 + Double(minute) * 60) }
    static func message(_ id: String, _ from: String, _ to: String, _ minute: Int?,
                        _ state: String = "answered", held: Bool = false) -> SeedTimelineInput {
        SeedTimelineInput(id: id, sender: from, recipient: to, state: state, held: held, date: minute.map(at))
    }

    static func main() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!

        // Input arrives newest first (as the Hub sends it); the timeline runs oldest → newest.
        let input = [message("c", "codex", "claude", 9, "held", held: true),
                     message("b", "claude", "gemini", 5, "failed"),
                     message("a", "claude", "codex", 2)]
        let l = SeedTimelineLayout.make(input, minWidth: 0, calendar: utc)
        check(l.edges.map(\.id) == ["a", "b", "c"], "edges run oldest to newest")
        check(l.lanes == ["claude", "codex", "gemini"], "lanes keep first-appearance order, sender first")
        check(l.edges.map(\.kind) == [.answered, .failed, .held], "state maps to edge kind")
        check(l.edges[1].x - l.edges[0].x == SeedTimelineLayout.step, "messages are spaced by order, not by clock gap")
        check(l.edges[2].from == 1 && l.edges[2].to == 0, "edge goes from the sender's lane to the recipient's lane")
        check(l.edges.last!.x + SeedTimelineLayout.run + SeedTimelineLayout.tail == l.width, "newest curve ends one tail before the right edge")

        // Narrow content is right-aligned so the newest sits next to "now".
        let wide = SeedTimelineLayout.make(input, minWidth: 900, calendar: utc)
        check(wide.width == 900, "content stretches to the visible width")
        check(wide.edges.last!.x + SeedTimelineLayout.run + SeedTimelineLayout.tail == 900, "short history hugs the right edge")
        check(wide.nowX < wide.width && wide.nowX > wide.edges.last!.x + SeedTimelineLayout.run, "now mark sits after the newest curve")

        // Held overrides the raw state; unknown states read as open.
        check(SeedEdgeKind.of(state: "claimed", held: true) == .held, "held flag wins over raw state")
        check(SeedEdgeKind.of(state: "needs_input", held: false) == .open, "needs_input is open work")
        check(SeedEdgeKind.of(state: "expired", held: false) == .failed, "expired reads as failed")
        check(SeedEdgeKind.of(state: "completed", held: false) == .answered, "completed reads as answered")

        // Time labels: one per minute change, never crowded.
        let crowd = (0..<6).map { message("m\($0)", "a", "b", $0 / 2) }
        let cl = SeedTimelineLayout.make(crowd, minWidth: 0, calendar: utc)
        check(Set(cl.ticks.map(\.label)).count == cl.ticks.count, "a minute is labelled once")
        check(zip(cl.ticks, cl.ticks.dropFirst()).allSatisfy { $1.x - $0.x >= 44 }, "labels keep at least 44 pt apart")

        // Equal or missing dates keep a stable order (older input position first).
        let ties = [message("new", "a", "b", 1), message("old", "a", "b", 1), message("undated", "a", "b", nil)]
        let tl = SeedTimelineLayout.make(ties, minWidth: 0, calendar: utc)
        check(tl.edges.map(\.id) == ["undated", "old", "new"], "ties and undated messages order stably")

        // Only the most recent `limit` messages are kept.
        let many = (0..<80).map { message("x\($0)", "a", "b", 80 - $0) }
        let ml = SeedTimelineLayout.make(many, minWidth: 0, limit: 60, calendar: utc)
        check(ml.edges.count == 60 && ml.edges.last!.id == "x0", "keeps the newest 60")

        // Hit-testing follows the curve, not its bounding box.
        let lane: CGFloat = 32
        let e = l.edges[0]
        let mid = SeedTimelineLayout.point(on: SeedTimelineLayout.curve(e, laneHeight: lane), t: 0.5)
        check(l.hit(mid, laneHeight: lane)?.id == "a", "a point on the curve hits it")
        check(l.hit(CGPoint(x: mid.x, y: mid.y + 40), laneHeight: lane) == nil, "far from every curve hits nothing")
        let selfLoop = SeedTimelineLayout.make([message("s", "a", "a", 1)], minWidth: 0, calendar: utc)
        let loop = SeedTimelineLayout.curve(selfLoop.edges[0], laneHeight: lane)
        check(SeedTimelineLayout.point(on: loop, t: 0.5).y < SeedTimelineLayout.laneY(0, laneHeight: lane), "a message to oneself bulges upward")

        check(SeedTimelineLayout.make([], minWidth: 300).edges.isEmpty, "empty input draws nothing")

        if failures == 0 { print("SeedTimelineLayoutTests: all passed") } else { exit(1) }
    }
}
