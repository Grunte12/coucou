import Foundation

@main
enum CoucouAgentPaneTests {
    static func summary(_ rid: String, _ at: String, state: String = "replied") -> HubTincanTraceSummary {
        let json = #"{"id":"\#(rid)","request_id":"\#(rid)","trace_id":"t-\#(rid)","from":"muse","to":"codex","state":"\#(state)","title":"hidden title","created_at":"\#(at)"}"#
        return try! JSONDecoder().decode(HubTincanTraceSummary.self, from: Data(json.utf8))
    }

    static func agent(_ id: String, name: String? = nil) -> HubTincanAgent {
        let json = #"{"id":"\#(id)","name":"\#(name ?? id)","online":true,"queued":0,"claimed":0}"#
        return try! JSONDecoder().decode(HubTincanAgent.self, from: Data(json.utf8))
    }

    static func main() throws {
        // Friendly names are presentation only; mixed-case names pass through untouched.
        precondition(CoucouHubFormat.display("claude-code") == "Claude Code")
        precondition(CoucouHubFormat.display("linkhub-muse") == "Muse")
        precondition(CoucouHubFormat.display("grokbot") == "Grokbot")
        precondition(CoucouHubFormat.display("MuseBot") == "MuseBot")
        precondition(CoucouHubFormat.display("  ") == "Unknown")

        // Colour is stable per identity and always from the Coucou palette.
        precondition(CoucouHubFormat.color(for: "codex") == CoucouHubFormat.color(for: "codex"))
        precondition(CoucouHubFormat.palette.contains(CoucouHubFormat.color(for: "cursor")))

        // Diagnostic agents are detected; real ones are not.
        precondition(CoucouHubFormat.isDiagnostic(agent("smoke-agent")))
        precondition(CoucouHubFormat.isDiagnostic(agent("x", name: "Probe 2")))
        for real in ["muse", "grokbot", "codex", "cursor", "claude-code", "opencode", "latest-agent", "attest"] {
            precondition(!CoucouHubFormat.isDiagnostic(agent(real)), real)
        }

        // Review rules: only terminal states are closed; held / needs_input are not.
        precondition(CoucouHubFormat.isClosed("replied") && CoucouHubFormat.isClosed("Denied"))
        precondition(!CoucouHubFormat.isClosed("held") && !CoucouHubFormat.isClosed("needs_input"))
        precondition(CoucouHubFormat.stateWord("needs_input") == "Input")

        // Transfers: newest first, merged by request ID, ties broken by request ID, bounded text.
        let inboxJSON = #"{"status":"ready","enabled":true,"held_count":1,"held_truncated":false,"held":[{"id":"b","request_id":"b","trace_id":"t-b","from":"muse","to":"codex","state":"held","title":"x","created_at":"2026-10-06T10:00:00Z"}],"traces":[{"id":"a","request_id":"a","trace_id":"t-a","from":"muse","to":"codex","state":"replied","title":"x","created_at":"2026-10-06T09:00:00Z"},{"id":"b","request_id":"b","trace_id":"t-b","from":"muse","to":"codex","state":"held","title":"x","created_at":"2026-10-06T10:00:00Z"},{"id":"c","request_id":"c","trace_id":"t-c","from":"codex","to":"muse","state":"replied","title":"x","created_at":"2026-10-06T10:00:00Z"}]}"#
        let inbox = try JSONDecoder().decode(HubTincanInbox.self, from: Data(inboxJSON.utf8))
        let ordered = CoucouHubFormat.transfers(inbox).map(\.requestID)
        precondition(ordered == ["c", "b", "a"], "\(ordered)")
        let chronological = HubTincanInbox(status: .ready, enabled: true, heldCount: 0,
            heldTruncated: false, traces: [summary("early", "2026-10-06T10:00:00Z"),
                                         summary("later", "2026-10-06T10:00:00.123Z")], held: [])
        precondition(CoucouHubFormat.transfers(chronological).map(\.requestID) == ["later", "early"])
        precondition(CoucouHubFormat.bounded(String(repeating: "x", count: 50), limit: 10).count == 11)
        precondition(CoucouHubFormat.relative(nil) == "—")
        precondition(CoucouHubFormat.date("2026-10-06T10:00:00Z") != nil)
        _ = summary("z", "2026-10-06T10:00:00Z")
        print("CoucouAgentPaneTests passed")
    }
}
