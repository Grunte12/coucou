#if COUCOU_HUB
import Foundation

/// Text and formatting for the Shelf, Clipboard and Usage panes. Foundation
/// only, so it can be exercised without AppKit or SwiftUI.
/// Working product name shown in the notch UI. A placeholder until the owner
/// picks the final name; change it here only. Code identifiers keep "Coucou".
enum CoucouBrand {
    static let name = "Seed"
}

enum CoucouWorkspaceFormat {
    /// "just now", "2 min ago", "3 h ago", "2 d ago". A future date reads as "just now".
    static func ago(_ date: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        guard seconds.isFinite, seconds >= 60 else { return "just now" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes) min ago" }
        let hours = minutes / 60
        if hours < 48 { return "\(hours) h ago" }
        return "\(hours / 24) d ago"
    }

    /// "in 12 min", "in 3 h 12 min", "in 2 d 4 h". Callers handle dates that have passed.
    static func until(_ date: Date, now: Date = Date()) -> String {
        let seconds = date.timeIntervalSince(now)
        guard seconds.isFinite, seconds >= 60 else { return "in under a minute" }
        let totalMinutes = Int(seconds / 60)
        let days = totalMinutes / 1_440
        let hours = (totalMinutes % 1_440) / 60
        let minutes = totalMinutes % 60
        if days > 0 { return hours > 0 ? "in \(days) d \(hours) h" : "in \(days) d" }
        if hours > 0 { return minutes > 0 ? "in \(hours) h \(minutes) min" : "in \(hours) h" }
        return "in \(minutes) min"
    }

    static func fileSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, bytes), countStyle: .file)
    }

    /// One-line preview: whitespace runs collapse, long text is cut with an ellipsis.
    static func preview(_ text: String, limit: Int = 160) -> String {
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard collapsed.count > limit else { return collapsed }
        return String(collapsed.prefix(max(0, limit - 1))) + "…"
    }

    // MARK: Usage

    static func windowTitle(_ id: String) -> String {
        switch id {
        case "five-hour": return "5 hours"
        case "seven-day": return "Week"
        default: return id
        }
    }

    static func usedText(_ window: CoucouUsageSnapshot.Window) -> String {
        "\(Int(window.usedPercent.rounded()))% used"
    }

    /// An elapsed reset is stale evidence, never "0% used".
    static func resetText(_ window: CoucouUsageSnapshot.Window, now: Date = Date()) -> String {
        window.resetsAt <= now
            ? "Reset passed · waiting for new data"
            : "Resets \(until(window.resetsAt, now: now))"
    }

    /// Detail line for one window. Once its reset has passed, the recorded
    /// numbers describe a window that is over, so only the reset state shows.
    static func windowDetail(_ window: CoucouUsageSnapshot.Window, now: Date = Date()) -> String {
        guard window.resetsAt > now else { return resetText(window, now: now) }
        return "\(usedText(window)) · \(Int(window.remainingPercent.rounded()))% left · \(resetText(window, now: now))"
    }

    static func staleReason(_ snapshot: CoucouUsageSnapshot, maximumAge: TimeInterval = 900,
                            now: Date = Date()) -> String? {
        guard snapshot.availability == .stale else { return nil }
        if snapshot.windows.contains(where: { $0.resetsAt <= now }) { return "A reset time has passed." }
        return "Older than \(Int(maximumAge / 60)) min."
    }

    static func providerName(_ id: String) -> String {
        switch id {
        case "claude-code": return "Claude Code"
        case "codex": return "Codex"
        case "gemini-cli": return "Gemini CLI"
        case "antigravity": return "Antigravity"
        default: return id
        }
    }

    static func sourceName(_ source: String?) -> String {
        switch source {
        case "existing-statusline-relay": return "Claude Code statusline relay (opt-in)"
        case .some(let other): return other
        case nil: return "No supported source yet"
        }
    }
}
#endif
