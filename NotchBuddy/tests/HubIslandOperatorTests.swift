import Foundation

actor OperatorFixtureAPI: HubIslandAPI {
    enum InboxMode { case healthy, permissionRequired, offline }

    private var inboxMode: InboxMode = .healthy
    private var inboxModeAfterDecision: InboxMode?
    private var decisionError: HubIslandAPIError?
    private var delayTraceReads = false
    private var delayInboxReads = false
    private var inbox: HubTincanInbox
    private var inboxReadCount = 0
    private var traceReadCount = 0
    private var decisionCallCount = 0
    private var decisionRequests: [(String, HubTincanDecision)] = []

    init() {
        let needsInput = Self.summary("trace-needs-input", "request-needs-input", "trace-needs-input",
                                      "receiver-a", "operator", "needs_input", "Receiver permission")
        let held = Self.summary("request-held-1", "request-held-1", "trace-held-1",
                                "agent-a", "agent-b", "held", "Review this bounded request")
        inbox = HubTincanInbox(status: .ready, enabled: true, heldCount: 1, heldTruncated: false,
                               traces: [needsInput], held: [held])
    }

    private static func summary(_ id: String, _ requestID: String, _ traceID: String,
                                _ sender: String, _ recipient: String, _ state: String,
                                _ title: String) -> HubTincanTraceSummary {
        HubTincanTraceSummary(id: id, requestID: requestID, traceID: traceID,
                              sender: sender, recipient: recipient, state: state,
                              title: title, createdAt: "2026-10-03T10:00:00Z")
    }

    func setInbox(_ value: HubTincanInbox) { inbox = value }
    func setInboxMode(_ value: InboxMode) { inboxMode = value }
    func setInboxModeAfterDecision(_ value: InboxMode?) { inboxModeAfterDecision = value }
    func setDecisionError(_ value: HubIslandAPIError?) { decisionError = value }
    func setDelayTraceReads(_ value: Bool) { delayTraceReads = value }
    func setDelayInboxReads(_ value: Bool) { delayInboxReads = value }
    func counts() -> (inbox: Int, trace: Int, decisions: Int) { (inboxReadCount, traceReadCount, decisionCallCount) }
    func recordedDecisions() -> [(String, HubTincanDecision)] { decisionRequests }

    func requestPairing() async throws -> HubPairingRequest { throw HubIslandAPIError.invalidResponse }
    func claimPairing(_ pairing: HubPairingRequest) async throws -> HubPairingClaim { .pending }
    func snapshot(credential: String) async throws -> HubSnapshot {
        HubSnapshot(revision: 1, hub: HubServiceHealth(status: "ready"), providers: [], jobs: [])
    }
    func updateTool(credential: String, update: HubToolUpdate) async throws -> HubSnapshot {
        throw HubIslandAPIError.invalidResponse
    }

    func tincanInbox(credential: String) async throws -> HubTincanInbox {
        inboxReadCount += 1
        if delayInboxReads { try await Task.sleep(for: .milliseconds(100)) }
        switch inboxMode {
        case .healthy: return inbox
        case .permissionRequired: throw HubIslandAPIError.operatorPermissionRequired
        case .offline: throw HubIslandAPIError.unreachable
        }
    }

    func tincanTrace(credential: String, traceID: String) async throws -> HubTincanTrace {
        traceReadCount += 1
        if delayTraceReads { try? await Task.sleep(for: .milliseconds(100)) }
        let summary = inbox.held.first(where: { $0.traceID == traceID })
            ?? inbox.traces.first(where: { $0.traceID == traceID })
        let step = HubTincanStep(id: "step-1", sender: summary?.sender ?? "agent-a",
            recipient: summary?.recipient ?? "agent-b", state: summary?.state ?? "running",
            kind: "ask", body: "Bounded request details", createdAt: "2026-10-03T10:01:00Z",
            reply: nil, exchanges: [], progress: nil)
        let event = HubTincanEvent(sequence: 1, event: "held", actor: "agent-b",
            requestID: summary?.requestID, at: "2026-10-03T10:01:02Z")
        return HubTincanTrace(traceID: traceID, steps: [step], events: [event])
    }

    func decideTincanRequest(credential: String, requestID: String,
                             decision: HubTincanDecision) async throws -> HubTincanDecisionAcknowledgement {
        decisionCallCount += 1
        if let decisionError { throw decisionError }
        guard inbox.held.contains(where: { $0.requestID == requestID }) else {
            throw HubIslandAPIError.decisionConflict
        }
        decisionRequests.append((requestID, decision))
        let remaining = inbox.held.filter { $0.requestID != requestID }
        inbox = HubTincanInbox(status: inbox.status, enabled: inbox.enabled, heldCount: remaining.count,
                               heldTruncated: false, traces: inbox.traces, held: remaining)
        if let inboxModeAfterDecision { inboxMode = inboxModeAfterDecision }
        return HubTincanDecisionAcknowledgement(requestID: requestID, decision: decision, status: "completed")
    }
}

@main
enum HubIslandOperatorTests {
    @MainActor
    private static func wait(until condition: () -> Bool, message: String) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        preconditionFailure(message)
    }

    @MainActor
    private static func waitForInboxRead(_ api: OperatorFixtureAPI, after count: Int) async throws {
        for _ in 0..<200 {
            if await api.counts().inbox > count { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        preconditionFailure("Metadata poll did not issue a new inbox request")
    }

    @MainActor
    static func main() async throws {
        try await testMetadataAndExactApproval()
        try await testStaleDecisionIsNeverRetried()
        try await testAcknowledgementNeedsFreshState()
        try await testPermissionAndCancellation()
        try await testPollingRecoveryAndRestart()
        try await testExplicitDetailRefresh()
        try await testDenialAndUncertainDecision()
        print("Hub Island operator: metadata polling/recovery/restart, held-ID dedupe, explicit detail refresh, hidden-refresh cancellation, exact approval/denial, uncertain no-replay, stale blocking and permission passed")
    }

    @MainActor
    private static func testDenialAndUncertainDecision() async throws {
        for uncertain in [false, true] {
            let api = OperatorFixtureAPI()
            let model = HubIslandModel(api: api, loadCredential: { "fixture-scoped-credential" })
            model.startOperatorPolling()
            try await wait(until: { model.tincanAccess == .ready }, message: "Denial baseline failed")
            model.readTincanTask(model.tincanInbox!.held[0])
            try await wait(until: { model.canDecideSelectedTincanTask }, message: "Denial detail failed")
            if uncertain { await api.setDecisionError(.unreachable) }
            model.decideSelectedTincanTask(.deny)
            try await wait(until: { model.activeDecisionRequestID == nil }, message: "Denial did not settle")
            if !uncertain {
                precondition(model.decisionResultMessage?.contains("Denial accepted") == true)
                let requests = await api.recordedDecisions()
                precondition(requests.count == 1 && requests[0].1 == .deny)
            }
            precondition(!model.canDecideSelectedTincanTask)
            model.decideSelectedTincanTask(.deny)
            model.decideSelectedTincanTask(.approve)
            let calls = await api.counts().decisions
            precondition(calls == 1) // Neither retry nor opposite decision on ambiguous result.
            model.stopOperatorPolling()
        }
    }

    @MainActor
    private static func testExplicitDetailRefresh() async throws {
        let api = OperatorFixtureAPI()
        let model = HubIslandModel(api: api, loadCredential: { "fixture-scoped-credential" })
        model.startOperatorPolling()
        try await wait(until: { model.tincanAccess == .ready }, message: "Detail-refresh baseline failed")
        let held = model.tincanInbox!.held[0]
        model.readTincanTask(held)
        try await wait(until: { model.selectedTincanTrace != nil && !model.isReadingTincanTrace },
                       message: "Initial trace failed")
        let answered = HubTincanTraceSummary(id: held.id, requestID: held.requestID,
            traceID: held.traceID, sender: held.sender, recipient: held.recipient,
            state: "answered", title: held.title, createdAt: held.createdAt)
        await api.setInbox(HubTincanInbox(status: .ready, enabled: true, heldCount: 0,
            heldTruncated: false, traces: [answered], held: []))
        model.refreshOperatorTasks()
        try await wait(until: { model.selectedTincanTrace?.steps.first?.state == "answered" },
                       message: "Explicit refresh left stale trace details")
        precondition(model.selectedTincanTask?.state == "answered")
        precondition(!model.canDecideSelectedTincanTask)
        let count = await api.counts().trace
        precondition(count == 2)
        await api.setDelayInboxReads(true)
        let reads = await api.counts().inbox
        model.refreshOperatorTasks()
        try await waitForInboxRead(api, after: reads)
        model.panelHidden()
        try await Task.sleep(for: .milliseconds(140))
        let hiddenTraceReads = await api.counts().trace
        precondition(hiddenTraceReads == count) // A late refresh cannot reopen hidden details.
        model.stopOperatorPolling()
    }

    @MainActor
    private static func testPollingRecoveryAndRestart() async throws {
        let api = OperatorFixtureAPI()
        let model = HubIslandModel(api: api, loadCredential: { "fixture-scoped-credential" },
            operatorPollSleep: { _ in try await Task.sleep(for: .milliseconds(20)) })
        model.startOperatorPolling()
        try await wait(until: { model.tincanAccess == .ready }, message: "Polling baseline failed")
        precondition(model.operatorPollingInterval == .seconds(2))
        await api.setInboxMode(.offline)
        try await wait(until: { model.tincanAccess == .offline }, message: "Offline state was not synchronized")
        precondition(model.operatorPollingInterval == .seconds(30))
        await api.setInboxMode(.healthy)
        try await wait(until: { model.tincanAccess == .ready }, message: "Polling did not recover without manual refresh")
        await api.setInbox(HubTincanInbox(status: .ready, enabled: true, heldCount: 0,
            heldTruncated: false, traces: [], held: []))
        try await wait(until: { model.tincanInbox?.heldCount == 0 }, message: "Idle state did not synchronize")
        precondition(model.operatorPollingInterval == .seconds(10))
        // Exercise overlapping cancellation cleanup and replacement generations.
        for _ in 0..<5 {
            model.stopOperatorPolling()
            model.startOperatorPolling()
            try await Task.sleep(for: .milliseconds(5))
        }
        let reads = await api.counts().inbox
        try await waitForInboxRead(api, after: reads)
        let traces = await api.counts().trace
        precondition(traces == 0) // Background recovery never pulls message bodies.
        model.stopOperatorPolling()
        try await Task.sleep(for: .milliseconds(30))
        let stopped = await api.counts().inbox
        try await Task.sleep(for: .milliseconds(50))
        let afterStop = await api.counts().inbox
        precondition(afterStop == stopped)
    }

    @MainActor
    private static func testMetadataAndExactApproval() async throws {
        let api = OperatorFixtureAPI()
        let model = HubIslandModel(api: api, loadCredential: { "fixture-scoped-credential" })
        var newHeldIDs: [[String]] = []
        model.onNewHeldRequests = { entries in newHeldIDs.append(entries.map(\.requestID)) }
        model.startOperatorPolling()
        try await wait(until: { model.tincanAccess == .ready && !model.isRefreshingTincan }, message: "Initial poll failed")
        precondition(newHeldIDs.isEmpty) // Existing held requests establish the baseline without a burst.

        let initialReads = await api.counts().inbox
        model.panelHidden()
        model.refreshOperatorTasks()
        try await waitForInboxRead(api, after: initialReads)
        try await wait(until: { !model.isRefreshingTincan }, message: "Hidden-panel metadata read did not settle")
        let hiddenReads = await api.counts().inbox
        precondition(hiddenReads > initialReads) // panelHidden leaves the background poller active.

        let existing = model.tincanInbox!.held[0]
        await api.setInbox(HubTincanInbox(status: .ready, enabled: true, heldCount: 1, heldTruncated: false,
            traces: [model.tincanInbox!.traces[0], existing], held: [existing]))
        model.refreshOperatorTasks()
        try await wait(until: { model.tincanInbox?.traces.count == 2 }, message: "Duplicate fixture did not load")
        precondition(model.nonHeldTincanTraces.map(\.requestID) == ["request-needs-input"])
        let second = HubTincanTraceSummary(id: "request-held-2", requestID: "request-held-2",
            traceID: "trace-held-2", sender: "agent-c", recipient: "agent-d", state: "held",
            title: "A second request", createdAt: "2026-10-03T10:02:00Z")
        let needsInput = model.tincanInbox!.traces[0]
        await api.setInbox(HubTincanInbox(status: .ready, enabled: true, heldCount: 2, heldTruncated: false,
                                          traces: [needsInput], held: [existing, second]))
        model.refreshOperatorTasks()
        try await wait(until: { model.tincanInbox?.held.count == 2 }, message: "New held metadata did not arrive")
        precondition(newHeldIDs == [["request-held-2"]])
        let readsBeforeDedupe = await api.counts().inbox
        model.refreshOperatorTasks()
        try await waitForInboxRead(api, after: readsBeforeDedupe)
        try await wait(until: { !model.isRefreshingTincan }, message: "Repeated poll did not settle")
        precondition(newHeldIDs.count == 1) // A given ID gets only one peek.

        model.readTincanTask(needsInput)
        try await wait(until: { !model.isReadingTincanTrace }, message: "Needs-input read did not settle")
        precondition(!model.canDecideSelectedTincanTask) // needs_input is never elevated to held.
        model.closeTincanTaskDetail()

        model.readTincanTask(existing)
        try await wait(until: { model.selectedTincanTrace != nil }, message: "Held details did not load")
        precondition(model.selectedTincanTrace?.steps.first?.body == "Bounded request details")
        precondition(model.canDecideSelectedTincanTask)
        model.decideSelectedTincanTask(.approve)
        try await wait(until: {
            model.activeDecisionRequestID == nil && model.decisionResultMessage?.contains("Approval accepted") == true
        }, message: "Successful approval was not acknowledged")
        let decisions = await api.recordedDecisions()
        precondition(decisions.count == 1 && decisions[0].0 == existing.requestID && decisions[0].1 == .approve)
        precondition(model.tincanInbox?.held.contains(where: { $0.requestID == existing.requestID }) == false)
        precondition(!model.canDecideSelectedTincanTask)
        let decisionCount = await api.counts().decisions
        model.decideSelectedTincanTask(.approve)
        let afterSecondTap = await api.counts().decisions
        precondition(afterSecondTap == decisionCount) // One POST per exact request ID.
        model.stopOperatorPolling()
    }

    @MainActor
    private static func testStaleDecisionIsNeverRetried() async throws {
        let api = OperatorFixtureAPI()
        let model = HubIslandModel(api: api, loadCredential: { "fixture-scoped-credential" })
        model.startOperatorPolling()
        try await wait(until: { model.tincanAccess == .ready }, message: "Stale-case inbox did not arrive")
        let held = model.tincanInbox!.held[0]
        model.readTincanTask(held)
        try await wait(until: { model.selectedTincanTrace != nil }, message: "Stale-case detail did not arrive")
        await api.setDecisionError(.decisionConflict)
        model.decideSelectedTincanTask(.approve)
        try await wait(until: {
            model.activeDecisionRequestID == nil && model.decisionResultMessage?.contains("stale") == true
        }, message: "409 conflict was not surfaced")
        let firstCount = await api.counts().decisions
        precondition(firstCount == 1 && !model.canDecideSelectedTincanTask)
        model.decideSelectedTincanTask(.approve)
        let secondCount = await api.counts().decisions
        precondition(secondCount == firstCount)
        model.stopOperatorPolling()
    }

    @MainActor
    private static func testPermissionAndCancellation() async throws {
        let permissionAPI = OperatorFixtureAPI()
        let permissionModel = HubIslandModel(api: permissionAPI, loadCredential: { "legacy-app-credential" })
        permissionModel.refresh()
        try await wait(until: { permissionModel.connection == .connected }, message: "Base snapshot failed")
        await permissionAPI.setInboxMode(.permissionRequired)
        permissionModel.startOperatorPolling()
        try await wait(until: { permissionModel.tincanAccess == .permissionRequired }, message: "403 did not request operator permission")
        precondition(permissionModel.connection == .connected && !permissionModel.canPair)
        permissionModel.stopOperatorPolling()

        let delayedAPI = OperatorFixtureAPI()
        await delayedAPI.setDelayTraceReads(true)
        let delayedModel = HubIslandModel(api: delayedAPI, loadCredential: { "fixture-scoped-credential" })
        delayedModel.startOperatorPolling()
        try await wait(until: { delayedModel.tincanAccess == .ready }, message: "Cancellation-case inbox failed")
        delayedModel.readTincanTask(delayedModel.tincanInbox!.held[0])
        try await wait(until: { delayedModel.isReadingTincanTrace }, message: "Trace read did not start")
        delayedModel.panelHidden()
        try await Task.sleep(for: .milliseconds(140))
        precondition(delayedModel.selectedTincanTrace == nil && !delayedModel.isReadingTincanTrace)
        delayedModel.stopOperatorPolling()
    }

    @MainActor
    private static func testAcknowledgementNeedsFreshState() async throws {
        let api = OperatorFixtureAPI()
        let model = HubIslandModel(api: api, loadCredential: { "fixture-scoped-credential" })
        model.startOperatorPolling()
        try await wait(until: { model.tincanAccess == .ready }, message: "Ack-case inbox did not arrive")
        let held = model.tincanInbox!.held[0]
        model.readTincanTask(held)
        try await wait(until: { model.selectedTincanTrace != nil }, message: "Ack-case details did not arrive")
        await api.setInboxModeAfterDecision(.offline)
        model.decideSelectedTincanTask(.approve)
        try await wait(until: {
            model.activeDecisionRequestID == nil
                && model.decisionResultMessage?.contains("could not be confirmed") == true
        }, message: "The model claimed a resumed state without a fresh metadata read")
        precondition(model.decisionResultMessage?.contains("no longer held") == false)
        model.stopOperatorPolling()
    }
}
