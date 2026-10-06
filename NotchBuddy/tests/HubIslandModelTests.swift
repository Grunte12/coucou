import Foundation

actor FixtureAPI: HubIslandAPI {
    enum Mode { case healthy, offline, unauthorized, delayed }
    var mode: Mode = .healthy
    var calls = 0
    var updates: [HubToolUpdate] = []
    var revision = 8
    var enabled = true
    var account = "second"
    func configure(_ mode: Mode) { self.mode = mode }
    func advanceRevisionExternally() { revision += 1 }
    func requestPairing() async throws -> HubPairingRequest { throw HubIslandAPIError.invalidResponse }
    func claimPairing(_ pairing: HubPairingRequest) async throws -> HubPairingClaim { .pending }
    func snapshot(credential: String) async throws -> HubSnapshot {
        calls += 1
        switch mode {
        case .offline: throw HubIslandAPIError.unreachable
        case .unauthorized: throw HubIslandAPIError.unauthorized
        case .delayed:
            // Deliberately return after cancellation to test late-response protection.
            try? await Task.sleep(for: .milliseconds(100))
        case .healthy: break
        }
        let data = try JSONSerialization.data(withJSONObject: [
            "revision": revision,
            "hub": ["status": "ready"],
            "providers": [["id": "chatgpt", "enabled": enabled, "account": account,
                "selectable_accounts": ["second", "primary"],
                "health": ["status": "unhealthy"]]],
            "jobs": [["id": "j", "provider": "chatgpt", "capability": "bridge.chat",
                "state": "running", "created_at": "2026-10-02T10:00:00Z"]]
        ])
        return try JSONDecoder().decode(HubSnapshot.self, from: data)
    }
    func updateTool(credential: String, update: HubToolUpdate) async throws -> HubSnapshot {
        updates.append(update)
        guard update.revision == revision else { throw HubIslandAPIError.revisionConflict }
        if let newEnabled = update.enabled { enabled = newEnabled }
        if let newAccount = update.account { account = newAccount }
        revision += 1
        return try await snapshot(credential: credential)
    }
}

@main
enum ModelTests {
    @MainActor static func settled(_ model: HubIslandModel) async throws {
        for _ in 0..<100 {
            try await Task.sleep(for: .milliseconds(5))
            if !model.isBusy && model.connection != .checking { return }
        }
        preconditionFailure("Model did not settle")
    }

    @MainActor static func main() async throws {
        let api = FixtureAPI()
        let model = HubIslandModel(api: api, loadCredential: { "synthetic" })
        let startupCalls = await api.calls
        precondition(startupCalls == 0) // No startup request.
        precondition(model.connection == .notChecked)
        model.refresh()
        try await settled(model)
        precondition(model.connection == .connected)
        precondition(model.snapshot?.providers.first?.health.status == "unhealthy")
        precondition(model.snapshot?.jobs.first?.state == "running")

        // Positive control paths must use the server-returned revision and state.
        model.setEnabled(model.snapshot!.providers[0], enabled: false)
        try await settled(model)
        precondition(model.snapshot!.revision == 9 && !model.snapshot!.providers[0].enabled)
        model.selectAccount("primary", for: model.snapshot!.providers[0])
        try await settled(model)
        precondition(model.snapshot!.revision == 10 && model.snapshot!.providers[0].account == "primary")
        precondition(model.snapshot!.jobs[0].id == "j" && model.snapshot!.jobs[0].state == "running")
        let updateCount = await api.updates.count
        model.selectAccount("not-configured", for: model.snapshot!.providers[0])
        model.selectAccount("primary", for: model.snapshot!.providers[0])
        let unchangedCount = await api.updates.count
        precondition(updateCount == unchangedCount && !model.isBusy)
        model.setEnabled(model.snapshot!.providers[0], enabled: true)
        try await settled(model)
        precondition(model.snapshot!.providers[0].enabled)
        model.panelHidden()
        let hiddenCalls = await api.calls
        try await Task.sleep(for: .milliseconds(150))
        let afterHiddenCalls = await api.calls
        precondition(hiddenCalls == afterHiddenCalls) // No hidden polling.

        await api.configure(.offline)
        model.refresh()
        try await settled(model)
        precondition(model.connection == .offline && model.snapshot == nil)
        await api.configure(.delayed)
        model.refresh()
        try await Task.sleep(for: .milliseconds(10))
        model.panelHidden()
        try await Task.sleep(for: .milliseconds(150))
        precondition(model.connection == .offline && model.snapshot == nil && !model.isBusy)

        await api.configure(.unauthorized)
        model.refresh()
        try await settled(model)
        precondition(model.connection == .unauthorized && model.canPair)
        await api.configure(.healthy)
        model.refresh()
        try await settled(model)
        let staleSnapshotRevision = model.snapshot!.revision
        await api.advanceRevisionExternally() // Simulate another client saving first.
        model.setEnabled(model.snapshot!.providers[0], enabled: false)
        try await settled(model)
        precondition(model.connection == .error)
        let submittedUpdates = await api.updates
        let serverRevision = await api.revision
        let serverEnabled = await api.enabled
        precondition(submittedUpdates.last?.revision == staleSnapshotRevision)
        precondition(serverRevision == staleSnapshotRevision + 1)
        precondition(model.snapshot!.revision == staleSnapshotRevision && model.snapshot!.providers[0].enabled)
        precondition(serverEnabled) // The stale write did not change server state.
        precondition(model.errorMessage!.contains("Refresh"))

        let empty = HubIslandModel(api: api, loadCredential: { nil })
        empty.refresh()
        try await settled(empty)
        precondition(empty.connection == .unpaired && empty.canPair)
        print("Hub Island model: startup, health/jobs, saved toggles/accounts, invalid/no-op selection, hidden idle, offline, cancellation, unauthorized, stale-revision conflict and unpaired passed")
    }
}
