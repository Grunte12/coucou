import Foundation
import AppKit

// MARK: - Seed Lab fixtures
//
// In-memory stand-ins for the local Hub so the lab never touches the network,
// the Keychain or a real inbox. Decisions are acknowledged and forgotten.

extension Notification.Name {
    /// object: NSValue(point:) in workspace-pane coordinates, or nil when the pointer leaves.
    static let seedLabPointer = Notification.Name("seedLabPointer")
    /// object: CGFloat pan delta. Synthetic wheel events never reach a local event monitor.
    static let seedLabScroll = Notification.Name("seedLabScroll")
}

enum SeedLab {
    /// Window point of the workspace pane's origin (pane-local 44,42 is the mascot centre).
    static let paneOrigin = CGPoint(x: 49, y: 36)

    /// Private pasteboard: the lab never reads or writes the user's clipboard.
    nonisolated(unsafe) static let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.grunte.seed.lab.pasteboard"))
}

enum SeedLabFixture: String, CaseIterable {
    /// Connected, agents online, nothing held.
    case calm
    /// Connected, one agent working on a claimed task.
    case busy
    /// Connected, two requests held for approval.
    case approval
    /// The Hub does not answer.
    case offline
    /// Connected, but Tincan returns no agents.
    case empty
    /// Three agents, ten messages in every state (one held, one failed), for the timeline.
    case timeline
}

final class SeedLabFixtureAPI: HubIslandAPI, @unchecked Sendable {
    static let shared = SeedLabFixtureAPI()

    private let lock = NSLock()
    private var current: SeedLabFixture = .calm
    private(set) var decisions: [String] = []

    var fixture: SeedLabFixture {
        get { lock.withLock { current } }
        set { lock.withLock { current = newValue } }
    }

    private func decode<T: Decodable>(_ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private func reachable() throws -> SeedLabFixture {
        let f = fixture
        if f == .offline { throw HubIslandAPIError.unreachable }
        return f
    }

    func requestPairing() async throws -> HubPairingRequest { throw HubIslandAPIError.unreachable }
    func claimPairing(_ pairing: HubPairingRequest) async throws -> HubPairingClaim { throw HubIslandAPIError.unreachable }

    func snapshot(credential: String) async throws -> HubSnapshot {
        _ = try reachable()
        return try decode(#"{"revision":1,"hub":{"status":"ok"},"providers":[],"jobs":[]}"#)
    }

    func updateTool(credential: String, update: HubToolUpdate) async throws -> HubSnapshot {
        try await snapshot(credential: credential)
    }

    func tincanRoster(credential: String) async throws -> HubTincanRoster {
        let f = try reachable()
        if f == .empty { return try decode(#"{"status":"ready","enabled":true,"agents":[]}"#) }
        let now = ISO8601DateFormatter().string(from: Date())
        let claimed = f == .busy ? 1 : 0
        return try decode("""
        {"status":"ready","enabled":true,"agents":[
          {"id":"claude-notch","name":"claude-notch","online":true,"kind":"claude","wake":"hook","version":"1.4.0","last_active":"\(now)","queued":\(f == .approval ? 2 : 0),"claimed":\(claimed)},
          {"id":"codex-backend","name":"codex-backend","online":true,"kind":"codex","wake":"poll","version":"1.4.0","last_active":"\(now)","queued":0,"claimed":0},
          {"id":"gemini-research","name":"gemini-research","online":\(f == .timeline),"kind":"gemini","wake":"none","version":"1.3.2","last_active":"2026-10-06T09:12:00Z","queued":0,"claimed":0}
        ]}
        """)
    }

    func tincanInbox(credential: String) async throws -> HubTincanInbox {
        let f = try reachable()
        if f == .timeline { return try decode(Self.timelineInbox) }
        let held = f == .approval ? """
          {"id":"h1","request_id":"req-h1","trace_id":"tr-h1","from":"codex-backend","to":"claude-notch","state":"held","title":"Review the clipboard store change before merge","created_at":"2026-10-07T08:40:00Z"},
          {"id":"h2","request_id":"req-h2","trace_id":"tr-h2","from":"claude-notch","to":"codex-backend","state":"held","title":"Run the usage snapshot tests","created_at":"2026-10-07T08:42:00Z"}
        """ : ""
        let claimed = f == .busy ? """
          ,{"id":"t3","request_id":"req-t3","trace_id":"tr-t3","from":"codex-backend","to":"claude-notch","state":"claimed","title":"Polish the shelf drop hint","created_at":"2026-10-07T08:50:00Z"}
        """ : ""
        let heldCount = f == .approval ? 2 : 0
        return try decode("""
        {"status":"ready","enabled":true,"held_count":\(heldCount),"held_truncated":false,
         "traces":[
          {"id":"t1","request_id":"req-t1","trace_id":"tr-t1","from":"claude-notch","to":"codex-backend","state":"answered","title":"Confirm currentSnapshot() is read-only","created_at":"2026-10-07T07:58:00Z"},
          {"id":"t2","request_id":"req-t2","trace_id":"tr-t2","from":"codex-backend","to":"claude-notch","state":"answered","title":"Shelf rejects a 21st file","created_at":"2026-10-07T08:05:00Z"}
          \(claimed)
         ],
         "held":[\(held)]}
        """)
    }

    /// claude-notch ⇄ codex-backend ping-pong, with gemini-research pulled in.
    private static let timelineInbox = """
    {"status":"ready","enabled":true,"held_count":1,"held_truncated":false,
     "traces":[
      {"id":"m1","request_id":"req-m1","trace_id":"tr-m","from":"claude-notch","to":"codex-backend","state":"answered","title":"Is currentSnapshot() read-only?","created_at":"2026-10-07T09:02:00Z"},
      {"id":"m2","request_id":"req-m2","trace_id":"tr-m","from":"codex-backend","to":"claude-notch","state":"answered","title":"Yes; add a test pin for it","created_at":"2026-10-07T09:05:00Z"},
      {"id":"m3","request_id":"req-m3","trace_id":"tr-g","from":"claude-notch","to":"gemini-research","state":"answered","title":"Compare timeline formats for a 640x230 notch","created_at":"2026-10-07T09:07:00Z"},
      {"id":"m4","request_id":"req-m4","trace_id":"tr-g","from":"gemini-research","to":"claude-notch","state":"answered","title":"Swimlanes win; sequence diagrams are too tall","created_at":"2026-10-07T09:11:00Z"},
      {"id":"m5","request_id":"req-m5","trace_id":"tr-s","from":"codex-backend","to":"gemini-research","state":"failed","title":"Fetch Spotify now-playing schema","created_at":"2026-10-07T09:14:00Z"},
      {"id":"m6","request_id":"req-m6","trace_id":"tr-s","from":"codex-backend","to":"codex-backend","state":"answered","title":"Retry with cached schema","created_at":"2026-10-07T09:16:00Z"},
      {"id":"m7","request_id":"req-m7","trace_id":"tr-u","from":"claude-notch","to":"codex-backend","state":"claimed","title":"Wire the usage relay for Gemini","created_at":"2026-10-07T09:20:00Z"},
      {"id":"m8","request_id":"req-m8","trace_id":"tr-u","from":"gemini-research","to":"codex-backend","state":"needs_input","title":"Which quota window should the card show?","created_at":"2026-10-07T09:24:00Z"},
      {"id":"m9","request_id":"req-m9","trace_id":"tr-r","from":"codex-backend","to":"claude-notch","state":"queued","title":"Review the shelf staging change","created_at":"2026-10-07T09:27:00Z"}
     ],
     "held":[
      {"id":"m10","request_id":"req-m10","trace_id":"tr-r","from":"codex-backend","to":"claude-notch","state":"held","title":"Allow running the signing script for Seed.app","created_at":"2026-10-07T09:30:00Z"}
     ]}
    """

    func tincanTrace(credential: String, traceID: String) async throws -> HubTincanTrace {
        _ = try reachable()
        return try decode("""
        {"trace_id":"\(traceID)","steps":[
          {"id":"s1","from":"codex-backend","to":"claude-notch","state":"held","kind":"ask","body":"Fixture request body for \(traceID). Nothing here is real.","created_at":"2026-10-07T08:40:00Z","exchanges":[]}
        ],"events":[]}
        """)
    }

    func decideTincanRequest(credential: String, requestID: String,
                             decision: HubTincanDecision) async throws -> HubTincanDecisionAcknowledgement {
        lock.withLock { decisions.append("\(decision.rawValue):\(requestID)") }
        return try decode(#"{"request_id":"\#(requestID)","decision":"\#(decision.rawValue)","status":"recorded"}"#)
    }
}
