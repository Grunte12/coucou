import Foundation

@main
struct CoucouWorkspacePresentationTests {
    static var failures = 0
    static func check(_ ok: Bool, _ name: String) {
        if !ok { failures += 1; print("FAIL: \(name)") }
    }

    static func main() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        typealias F = CoucouWorkspaceFormat

        check(F.ago(now.addingTimeInterval(-10), now: now) == "just now", "ago under a minute")
        check(F.ago(now.addingTimeInterval(120), now: now) == "just now", "ago future")
        check(F.ago(now.addingTimeInterval(-150), now: now) == "2 min ago", "ago minutes")
        check(F.ago(now.addingTimeInterval(-3 * 3600), now: now) == "3 h ago", "ago hours")
        check(F.ago(now.addingTimeInterval(-3 * 86_400), now: now) == "3 d ago", "ago days")

        check(F.until(now.addingTimeInterval(30), now: now) == "in under a minute", "until seconds")
        check(F.until(now.addingTimeInterval(12 * 60 + 5), now: now) == "in 12 min", "until minutes")
        check(F.until(now.addingTimeInterval(3 * 3600 + 12 * 60), now: now) == "in 3 h 12 min", "until h min")
        check(F.until(now.addingTimeInterval(3 * 3600), now: now) == "in 3 h", "until exact hours")
        check(F.until(now.addingTimeInterval(2 * 86_400 + 4 * 3600), now: now) == "in 2 d 4 h", "until days")

        check(F.preview("  a \n\n b\tc ") == "a b c", "preview collapses whitespace")
        let long = String(repeating: "x", count: 500)
        check(F.preview(long, limit: 20).count == 20 && F.preview(long, limit: 20).hasSuffix("…"), "preview truncates")
        check(F.preview("short", limit: 20) == "short", "preview keeps short text")
        check(F.preview("", limit: 20) == "", "preview empty")

        check(F.windowTitle("five-hour") == "5 hours" && F.windowTitle("seven-day") == "Week", "window titles")
        check(F.providerName("claude-code") == "Claude Code", "provider name")
        check(F.providerName("a-very-long-provider-name-that-should-not-be-rewritten") ==
              "a-very-long-provider-name-that-should-not-be-rewritten", "unknown provider passes through")
        check(F.sourceName(nil) == "No supported source yet", "source none")

        // An elapsed reset must never read as an empty limit.
        let passed = CoucouUsageSnapshot.Window(id: "five-hour", usedPercent: 91, resetsAt: now.addingTimeInterval(-60))
        let passedText = F.resetText(passed, now: now)
        check(passedText.contains("passed") && !passedText.contains("0%"), "reset passed text")
        check(F.usedText(passed) == "91% used", "used text keeps recorded value")
        let upcoming = CoucouUsageSnapshot.Window(id: "seven-day", usedPercent: 12.4, resetsAt: now.addingTimeInterval(3 * 3600))
        check(F.resetText(upcoming, now: now) == "Resets in 3 h", "reset upcoming")
        check(F.usedText(upcoming) == "12% used", "used text rounds")
        check(F.windowDetail(passed, now: now) == "Reset passed · waiting for new data", "passed detail hides old numbers")
        check(F.windowDetail(upcoming, now: now) == "12% used · 88% left · Resets in 3 h", "upcoming detail")

        let stalePassed = CoucouUsageSnapshot(providerID: "claude-code", source: "existing-statusline-relay",
                                              observedAt: now, availability: .stale, windows: [passed])
        check(F.staleReason(stalePassed, now: now) == "A reset time has passed.", "stale reason reset")
        let staleOld = CoucouUsageSnapshot(providerID: "claude-code", source: "existing-statusline-relay",
                                           observedAt: now, availability: .stale, windows: [upcoming])
        check(F.staleReason(staleOld, now: now) == "Older than 15 min.", "stale reason age")
        let fresh = CoucouUsageSnapshot(providerID: "claude-code", source: "existing-statusline-relay",
                                        observedAt: now, availability: .available, windows: [upcoming])
        check(F.staleReason(fresh, now: now) == nil, "fresh has no stale reason")
        check(F.staleReason(.unavailable(providerID: "codex"), now: now) == nil, "unavailable has no stale reason")

        if failures > 0 { print("\(failures) failure(s)"); exit(1) }
        print("CoucouWorkspacePresentation tests passed")
    }
}
