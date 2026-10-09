#if COUCOU_HUB
import Foundation

/// Pure presentation helpers, kept free of views so they stay testable.
enum CoucouHubFormat {
    static let palette = ["#FF5A4E", "#2EC4A0", "#F29B38", "#7C5CFF", "#22D3EE", "#F472B6"]

    /// Stable per-identity colour (djb2, not `hashValue`, which varies per launch).
    static func color(for id: String) -> String {
        var h: UInt32 = 5381
        for b in id.utf8 { h = (h &* 33) &+ UInt32(b) }
        return palette[Int(h % UInt32(palette.count))]
    }

    /// Friendly label only; the wire identity is never rewritten.
    static func display(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Unknown" }
        if trimmed == "linkhub-muse" { return "Muse" }
        if trimmed == "opencode" { return "OpenCode" }
        guard trimmed == trimmed.lowercased() else { return trimmed }
        return trimmed
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    static func isDiagnostic(_ agent: HubTincanAgent) -> Bool {
        let words = (agent.id + " " + agent.name).lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        return words.contains { ["test", "diag", "probe", "smoke", "e2e", "fixture"].contains(String($0)) }
    }

    static func bounded(_ value: String, limit: Int) -> String {
        value.count > limit ? String(value.prefix(limit)) + "…" : value
    }

    static func pretty(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
    }

    static func date(_ value: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    static func relative(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "—" }
        guard let d = date(value) else { return bounded(value, limit: 24) }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: d, relativeTo: .now)
    }

    static func stateHex(_ raw: String) -> String {
        switch raw.lowercased() {
        case "held": return "#F5A524"
        case "needs_input": return "#F5A524"
        case "replied", "answered", "complete", "completed", "succeeded", "success", "approved", "ok", "ready", "healthy":
            return "#22C55E"
        case "denied", "declined", "failed", "error", "expired", "offline", "degraded", "unhealthy":
            return "#F4505E"
        case "running", "working", "claimed", "pending", "queued":
            return "#22D3EE"
        default: return "#8E939C"
        }
    }

    static func stateSymbol(_ raw: String) -> String {
        switch raw.lowercased() {
        case "held": return "hand.raised.fill"
        case "needs_input": return "questionmark.bubble.fill"
        case "running", "working", "claimed", "approved", "pending", "queued": return "circle.dotted"
        case "replied", "answered", "complete", "completed", "succeeded", "success": return "checkmark"
        case "denied", "declined": return "nosign"
        case "failed", "error", "expired": return "exclamationmark.triangle.fill"
        default: return "circle"
        }
    }

    static func stateWord(_ raw: String) -> String {
        raw.lowercased() == "needs_input" ? "Input" : pretty(raw).capitalized
    }

    /// Terminal states are read-only history, never approve-able.
    static func isClosed(_ raw: String) -> Bool {
        ["replied", "answered", "complete", "completed", "succeeded", "success",
         "denied", "declined", "failed", "error", "expired"].contains(raw.lowercased())
    }

    /// Compare communication revisions, not just IDs: replies reuse request IDs.
    static func changedTransfers(previous: [String: HubTincanTraceSummary], current: [HubTincanTraceSummary]) -> Set<String> {
        Set(current.filter { entry in
            guard let old = previous[entry.requestID] else { return true }
            return old.state != entry.state || old.activityAt != entry.activityAt
        }.map(\.requestID))
    }

    /// Newest first, stable on equal timestamps; held and traces merged by request ID.
    static func transfers(_ inbox: HubTincanInbox) -> [HubTincanTraceSummary] {
        var seen = Set<String>()
        var merged: [HubTincanTraceSummary] = []
        for entry in inbox.held + inbox.traces where seen.insert(entry.requestID).inserted {
            merged.append(entry)
        }
        // Parse once per row: RFC3339 offsets/fractional seconds are not safely
        // ordered lexically. Unknown dates stay at the end, with stable IDs.
        return merged.map { ($0, date($0.activityAt) ?? .distantPast) }
            .sorted { ($0.1, $0.0.requestID) > ($1.1, $1.0.requestID) }
            .map(\.0)
    }
}
#endif
