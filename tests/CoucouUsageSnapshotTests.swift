import Foundation

@main
enum UsageTests {
    static func main() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let future = now.addingTimeInterval(3600)
        func snapshot(_ pct: Double, observed: Date? = nil, reset: Date? = nil) -> CoucouUsageSnapshot {
            .claude(PlanUsage(fiveHour: PlanWindow(usedPct: pct, resetsAt: reset ?? future),
                              sevenDay: nil, updatedAt: observed ?? now), now: now)
        }
        let current = snapshot(37)
        precondition(current.availability == .available)
        precondition(current.windows[0].remainingPercent == 63)
        precondition(current.source == "existing-statusline-relay")
        precondition(snapshot(0).windows[0].remainingPercent == 100)
        precondition(snapshot(100).windows[0].remainingPercent == 0)
        precondition(snapshot(.nan).availability == .unavailable)
        precondition(snapshot(.infinity).availability == .unavailable)
        precondition(snapshot(-1).availability == .unavailable)
        precondition(snapshot(101).availability == .unavailable)
        precondition(CoucouUsageSnapshot.claude(nil, now: now).windows.isEmpty)
        precondition(snapshot(37, observed: now.addingTimeInterval(-901)).availability == .stale)
        precondition(snapshot(37, observed: now.addingTimeInterval(1)).availability == .unavailable)
        let expired = snapshot(37, reset: now.addingTimeInterval(-1))
        precondition(expired.availability == .stale && expired.windows[0].usedPercent == 37)
        let unknown = CoucouUsageSnapshot.unavailable(providerID: "grokbot")
        precondition(unknown.windows.isEmpty && unknown.observedAt == nil && unknown.source == nil)
        print("PASS: usage snapshot validation, fresh/stale/unknown and truthful reset semantics")
    }
}
