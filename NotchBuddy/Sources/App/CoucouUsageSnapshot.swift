import Foundation

/// Presentation data, not an authentication client. Reads only snapshots already
/// supplied by a provider integration; never opens credentials or starts polling.
struct CoucouUsageSnapshot {
    enum Availability: Equatable {
        case available, stale, unavailable
    }

    struct Window: Equatable {
        let id: String
        let usedPercent: Double
        let resetsAt: Date
        var remainingPercent: Double { max(0, 100 - usedPercent) }
    }

    let providerID: String
    let source: String?
    let observedAt: Date?
    let availability: Availability
    let windows: [Window]

    static func unavailable(providerID: String) -> Self {
        Self(providerID: providerID, source: nil, observedAt: nil,
             availability: .unavailable, windows: [])
    }

    /// Claude's existing opt-in statusline relay is the only wired source today.
    /// A reset that elapsed is stale evidence, not proof of a freshly empty limit.
    static func claude(_ usage: PlanUsage?, now: Date = Date(),
                       maximumAge: TimeInterval = 900) -> Self {
        guard let usage, usage.updatedAt.timeIntervalSince1970.isFinite,
              usage.updatedAt <= now else { return unavailable(providerID: "claude-code") }
        let candidates: [(String, PlanWindow?)] = [
            ("five-hour", usage.fiveHour), ("seven-day", usage.sevenDay)
        ]
        let valid = candidates.compactMap { id, candidate -> Window? in
            guard let window = candidate,
                  window.usedPct.isFinite, (0...100).contains(window.usedPct),
                  window.resetsAt.timeIntervalSince1970.isFinite else { return nil }
            return Window(id: id, usedPercent: window.usedPct, resetsAt: window.resetsAt)
        }
        guard !valid.isEmpty else { return unavailable(providerID: "claude-code") }
        let stale = !maximumAge.isFinite || maximumAge <= 0 ||
            now.timeIntervalSince(usage.updatedAt) > maximumAge ||
            valid.contains { $0.resetsAt <= now }
        return Self(providerID: "claude-code", source: "existing-statusline-relay",
                    observedAt: usage.updatedAt, availability: stale ? .stale : .available,
                    windows: valid)
    }
}
