import Foundation

@main
enum HubIslandContractTests {
    static func main() throws {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase

        precondition(HubIslandEndpoint.origin.absoluteString == "http://127.0.0.1:8768")
        precondition(HubIslandEndpoint.url("/api/island/snapshot").path == "/api/island/snapshot")
        precondition(HubIslandEndpoint.url("/api/island/tincan").path == "/api/island/tincan")

        let pairFixture = #"{"request_id":"pair-17","poll_secret":"fixture-poll-secret","expires_in":240}"#.data(using: .utf8)!
        let pair = try decoder.decode(HubPairingRequest.self, from: pairFixture)
        precondition(pair.requestId == "pair-17")
        precondition(pair.pollSecret == "fixture-poll-secret")
        precondition(pair.expiresIn == 240 && pair.isUsable)

        let approvalFixture = #"{"credential":"fixture-app-credential","expires_at":"2026-10-02T12:00:00Z"}"#.data(using: .utf8)!
        let approval = try decoder.decode(HubPairingApproval.self, from: approvalFixture)
        precondition(approval.credential == "fixture-app-credential")
        precondition(approval.expiresAt == "2026-10-02T12:00:00Z")

        let snapshotFixture = #"{"revision":7,"hub":{"status":"ready"},"providers":[{"id":"browser","enabled":true,"account":"primary","selectable_accounts":["primary","secondary"],"health":{"status":"healthy"}},{"id":"git","enabled":false,"account":null,"selectable_accounts":[],"health":{"status":"not_checked"}}],"jobs":[{"id":"job-1","provider":"browser","capability":"search","state":"running","created_at":"2026-10-02T10:00:00Z","updated_at":null},{"id":"job-2","provider":"git","capability":"commit","state":"completed","created_at":"2026-10-02T09:00:00Z","updated_at":"2026-10-02T09:01:00Z"}]}"#.data(using: .utf8)!
        let snapshot = try decoder.decode(HubSnapshot.self, from: snapshotFixture)
        precondition(snapshot.revision == 7 && snapshot.hub.status == "ready")
        precondition(snapshot.providers.count == 2)
        precondition(snapshot.providers[0].id == "browser")
        precondition(snapshot.providers[0].selectableAccounts == ["primary", "secondary"])
        precondition(snapshot.providers[1].account == nil)
        precondition(snapshot.providers[1].health.status == "not_checked")
        precondition(snapshot.jobs[0].createdAt == "2026-10-02T10:00:00Z")
        precondition(snapshot.jobs[0].updatedAt == nil)
        precondition(snapshot.jobs[1].updatedAt == "2026-10-02T09:01:00Z")

        let claim = HubPairingClaimBody(requestId: pair.requestId, pollSecret: pair.pollSecret)
        let claimObject = try JSONSerialization.jsonObject(with: encoder.encode(claim)) as! [String: Any]
        precondition(claimObject["request_id"] as? String == "pair-17")
        precondition(claimObject["poll_secret"] as? String == "fixture-poll-secret")

        let toggle = HubToolUpdate(revision: snapshot.revision, provider: "browser", enabled: false)
        let toggleObject = try JSONSerialization.jsonObject(with: encoder.encode(toggle)) as! [String: Any]
        precondition(toggleObject["revision"] as? Int == 7)
        precondition(toggleObject["provider"] as? String == "browser")
        precondition(toggleObject["enabled"] as? Bool == false)
        precondition(toggleObject["account"] == nil)

        let account = HubToolUpdate(revision: 7, provider: "browser", account: "secondary")
        let accountObject = try JSONSerialization.jsonObject(with: encoder.encode(account)) as! [String: Any]
        precondition(accountObject["account"] as? String == "secondary")
        precondition(accountObject["enabled"] == nil)

        let tincanFixture = #"{"status":"ready","enabled":true,"held_count":2,"held_truncated":true,"traces":[{"id":"trace-row-1","request_id":"req-running","trace_id":"trace-1","from":"agent-a","to":"agent-b","state":"needs_input","title":"Permission request","created_at":"2026-10-03T10:00:00Z"}],"held":[{"id":"req-held-1","request_id":"req-held-1","trace_id":"trace-held-1","from":"agent-c","to":"agent-d","state":"held","title":"Review this work","created_at":"2026-10-03T10:01:00Z"}]}"#.data(using: .utf8)!
        let tincan = try decoder.decode(HubTincanInbox.self, from: tincanFixture)
        precondition(tincan.status == .ready && tincan.enabled)
        precondition(tincan.heldCount == 2 && tincan.heldTruncated)
        precondition(tincan.traces[0].sender == "agent-a" && tincan.traces[0].recipient == "agent-b")
        precondition(tincan.traces[0].state == "needs_input" && tincan.traces[0].requestID == "req-running")
        precondition(tincan.held[0].requestID == "req-held-1" && tincan.held[0].state == "held")

        let traceFixture = #"{"trace_id":"trace-held-1","steps":[{"id":"step-1","from":"agent-c","to":"agent-d","state":"held","kind":"ask","body":"Bounded request body","created_at":"2026-10-03T10:01:00Z","reply":null,"exchanges":[{"question":"Q?","answer":"A.","at":"2026-10-03T10:01:05Z"}],"progress":{"note":"Checking","at":"2026-10-03T10:01:06Z","by":"agent-d"}}],"events":[{"seq":4,"event":"held","actor":"agent-d","request_id":"req-held-1","at":"2026-10-03T10:01:07Z"}]}"#.data(using: .utf8)!
        let trace = try decoder.decode(HubTincanTrace.self, from: traceFixture)
        precondition(trace.traceID == "trace-held-1" && trace.steps[0].body == "Bounded request body")
        precondition(trace.steps[0].exchanges[0].question == "Q?" && trace.steps[0].progress?.by == "agent-d")
        let pendingExchange = try decoder.decode(HubTincanExchange.self,
            from: Data(#"{"question":"Confirm scope?","answer":null,"at":"2026-10-05T10:00:00Z"}"#.utf8))
        precondition(pendingExchange.answer.isEmpty && pendingExchange.question == "Confirm scope?")
        precondition(trace.events[0].sequence == 4 && trace.events[0].requestID == "req-held-1")

        let ackFixture = #"{"request_id":"req-held-1","decision":"approve","status":"completed"}"#.data(using: .utf8)!
        let acknowledgement = try decoder.decode(HubTincanDecisionAcknowledgement.self, from: ackFixture)
        precondition(acknowledgement.requestID == "req-held-1")
        precondition(acknowledgement.decision == .approve && acknowledgement.status == "completed")
        let decisionBody = try JSONSerialization.jsonObject(with: encoder.encode(
            HubTincanDecisionBody(requestID: "req-held-1", decision: .deny)
        )) as! [String: Any]
        precondition(decisionBody["request_id"] as? String == "req-held-1")
        precondition(decisionBody["decision"] as? String == "deny")
        print("Hub Island contract fixtures: pairing, approval, providers, jobs, Tincan inbox/trace/decision ACK, toggle and account payloads passed")
    }
}
