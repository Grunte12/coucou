import Combine
import Foundation

enum HubIslandConnection: Equatable {
    case notChecked
    case checking
    case unpaired
    case awaitingApproval
    case connected
    case unauthorized
    case offline
    case error
}

enum HubIslandTincanAccess: Equatable {
    case notChecked
    case ready
    case needsCredential
    case permissionRequired
    case unauthorized
    case offline
    case error
}

@MainActor
final class HubIslandModel: ObservableObject {
    @Published var dashboardTab = "tools"
    @Published private(set) var connection: HubIslandConnection = .notChecked
    @Published private(set) var snapshot: HubSnapshot?
    @Published private(set) var pairing: HubPairingRequest?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isBusy = false
    @Published private(set) var busyProviders: Set<String> = []
    @Published private(set) var credentialAvailable: Bool?
    @Published private(set) var tincanAccess: HubIslandTincanAccess = .notChecked
    @Published private(set) var tincanInbox: HubTincanInbox?
    @Published private(set) var tincanErrorMessage: String?
    @Published private(set) var isRefreshingTincan = false
    @Published private(set) var selectedTincanTask: HubTincanTraceSummary?
    @Published private(set) var selectedTincanTrace: HubTincanTrace?
    @Published private(set) var isReadingTincanTrace = false
    @Published private(set) var tincanTraceErrorMessage: String?
    @Published private(set) var activeDecisionRequestID: String?
    @Published private(set) var decisionResultMessage: String?

    /// Called only for held request IDs first observed after the initial baseline.
    var onNewHeldRequests: (@MainActor ([HubTincanTraceSummary]) -> Void)?

    // A live pairing request must be checked, not replaced. Keeping the pending
    // request through transient claim errors also leaves the Check approval action
    // available; an expired request is cleared below so pairing can be retried.
    var canPair: Bool {
        pairing == nil && (credentialAvailable == false || connection == .unauthorized)
    }

    private let api: any HubIslandAPI
    private let loadCredential: @Sendable () async throws -> String?
    private var connectionBeforeRefresh: HubIslandConnection = .notChecked
    private var credential: String?
    private var operationTask: Task<Void, Never>?
    private var operationID: UUID?
    private var operatorPollingTask: Task<Void, Never>?
    private var operatorPollingID: UUID?
    private let operatorPollSleep: @Sendable (Duration) async throws -> Void
    private var operatorActionTask: Task<Void, Never>?
    private var operatorActionID: UUID?
    private var detailVisibilityGeneration = UUID()
    private var operatorCredentialLoaded = false
    private var operatorCredential: String?
    private var hasTincanBaseline = false
    private var knownHeldRequestIDs: Set<String> = []
    private var knownHeldRequestIDOrder: [String] = []
    private let rememberedHeldRequestLimit = 2_048
    private var attemptedDecisionRequestIDs: Set<String> = []
    private var blockedDecisionRequestIDs: Set<String> = []

    var heldRequestCount: Int { max(0, tincanInbox?.heldCount ?? tincanInbox?.held.count ?? 0) }

    var nonHeldTincanTraces: [HubTincanTraceSummary] {
        guard let inbox = tincanInbox else { return [] }
        let heldIDs = Set(inbox.held.map(\.requestID))
        return inbox.traces.filter { !heldIDs.contains($0.requestID) }
    }

    var canDecideSelectedTincanTask: Bool {
        guard tincanAccess == .ready,
              let selectedTincanTask,
              let detail = selectedTincanTrace,
              let inbox = tincanInbox,
              inbox.status == .ready,
              inbox.enabled,
              inbox.held.contains(where: {
                  $0.requestID == selectedTincanTask.requestID && $0.traceID == selectedTincanTask.traceID
              }),
              detail.traceID == selectedTincanTask.traceID,
              detail.events.contains(where: { $0.requestID == selectedTincanTask.requestID }),
              detail.steps.contains(where: { step in
                  !step.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      || !(step.reply?.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                      || step.exchanges.contains {
                          !$0.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      }
              }),
              !attemptedDecisionRequestIDs.contains(selectedTincanTask.requestID),
              !blockedDecisionRequestIDs.contains(selectedTincanTask.requestID),
              activeDecisionRequestID == nil,
              operatorActionTask == nil,
              !isRefreshingTincan,
              !isReadingTincanTrace else { return false }
        return true
    }

    init(api: any HubIslandAPI = HubIslandAPIClient(),
         loadCredential: @escaping @Sendable () async throws -> String? = {
             try await HubIslandModel.loadCredentialFromKeychain()
         },
         operatorPollSleep: @escaping @Sendable (Duration) async throws -> Void = {
             try await Task.sleep(for: $0)
         }) {
        self.api = api
        self.loadCredential = loadCredential
        self.operatorPollSleep = operatorPollSleep
    }

    /// Called by the panel when it becomes visible. No request is made at app launch.
    func refresh() {
        run { [weak self] in await self?.loadSnapshot() }
    }

    /// Polls only the local, metadata-only Tincan overview. It deliberately runs
    /// independently of panel visibility and never fetches trace bodies.
    func startOperatorPolling() {
        guard operatorPollingTask == nil else { return }
        let id = UUID()
        operatorPollingID = id
        operatorPollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                _ = await self.loadTincanInbox()
                do {
                    try await self.operatorPollSleep(self.operatorPollingInterval)
                } catch {
                    break
                }
            }
            // A cancelled generation must never clear a replacement poller.
            guard self.operatorPollingID == id else { return }
            self.operatorPollingTask = nil
            self.operatorPollingID = nil
        }
    }

    var operatorPollingInterval: Duration {
        guard tincanAccess == .ready, tincanInbox?.status == .ready,
              tincanInbox?.enabled == true else { return .seconds(30) }
        return heldRequestCount > 0 ? .seconds(2) : .seconds(10)
    }

    func stopOperatorPolling() {
        detailVisibilityGeneration = UUID()
        operatorPollingTask?.cancel()
        operatorPollingTask = nil
        operatorPollingID = nil
        operatorActionTask?.cancel()
        operatorActionTask = nil
        operatorActionID = nil
        isRefreshingTincan = false
        if activeDecisionRequestID != nil {
            decisionResultMessage = "Decision interrupted. Refresh the task list to verify the Hub state before taking another action."
        }
        activeDecisionRequestID = nil
        isReadingTincanTrace = false
    }

    func refreshOperatorTasks() {
        let visibilityGeneration = detailVisibilityGeneration
        Task { [weak self] in
            guard let self, await self.loadTincanInbox(), !Task.isCancelled else { return }
            // Explicit refresh reconciles an open detail too. Background polling
            // stays metadata-only and never downloads message bodies.
            if self.detailVisibilityGeneration == visibilityGeneration,
               let selected = self.selectedTincanTask,
               let latest = self.currentTincanTask(requestID: selected.requestID),
               latest.traceID == selected.traceID {
                self.readTincanTask(latest)
            }
        }
    }

    func readTincanTask(_ summary: HubTincanTraceSummary) {
        guard operatorActionTask == nil,
              tincanAccess == .ready,
              let current = currentTincanTask(requestID: summary.requestID),
              current.traceID == summary.traceID else { return }
        selectedTincanTask = current
        selectedTincanTrace = nil
        tincanTraceErrorMessage = nil
        decisionResultMessage = nil
        isReadingTincanTrace = true
        runOperatorAction { [weak self] in
            guard let self else { return }
            defer { if !Task.isCancelled { self.isReadingTincanTrace = false } }
            do {
                guard let credential = try await self.operatorAuthorizationCredential() else {
                    self.tincanAccess = .needsCredential
                    return
                }
                let trace = try await self.api.tincanTrace(credential: credential, traceID: current.traceID)
                try Task.checkCancellation()
                guard trace.traceID == current.traceID else { throw HubIslandAPIError.invalidResponse }
                self.selectedTincanTrace = trace
            } catch is CancellationError {
                return
            } catch let error as HubIslandAPIError {
                guard !Task.isCancelled else { return }
                self.showTincan(error)
                self.tincanTraceErrorMessage = error.localizedDescription
            } catch {
                guard !Task.isCancelled else { return }
                self.tincanAccess = .error
                self.tincanTraceErrorMessage = "Could not read this task’s bounded trace details."
            }
        }
    }

    func closeTincanTaskDetail() {
        detailVisibilityGeneration = UUID()
        operatorActionTask?.cancel()
        operatorActionTask = nil
        operatorActionID = nil
        if activeDecisionRequestID != nil {
            decisionResultMessage = "Decision interrupted. Refresh the task list to verify the Hub state before taking another action."
        }
        activeDecisionRequestID = nil
        isReadingTincanTrace = false
        selectedTincanTask = nil
        selectedTincanTrace = nil
        tincanTraceErrorMessage = nil
    }

    func decideSelectedTincanTask(_ decision: HubTincanDecision) {
        guard canDecideSelectedTincanTask,
              let selected = selectedTincanTask else { return }
        let requestID = selected.requestID
        // Mark before sending. A timeout/cancel has an ambiguous result, so this
        // app never replays a user decision automatically or twice for one ID.
        attemptedDecisionRequestIDs.insert(requestID)
        activeDecisionRequestID = requestID
        decisionResultMessage = nil
        runOperatorAction { [weak self] in
            guard let self else { return }
            defer { if !Task.isCancelled { self.activeDecisionRequestID = nil } }
            do {
                guard let credential = try await self.operatorAuthorizationCredential() else {
                    self.tincanAccess = .needsCredential
                    self.decisionResultMessage = "No Hub Island credential is installed. The decision was not sent."
                    return
                }
                let acknowledgement = try await self.api.decideTincanRequest(
                    credential: credential, requestID: requestID, decision: decision
                )
                try Task.checkCancellation()
                guard acknowledgement.requestID == requestID, acknowledgement.decision == decision else {
                    throw HubIslandAPIError.invalidResponse
                }
                self.decisionResultMessage = decision == .approve
                    ? "Approval recorded by the Hub. Checking the task state…"
                    : "Denial recorded by the Hub. Checking the task state…"
                let refreshed = await self.loadTincanInbox(waitForInFlight: true)
                try Task.checkCancellation()
                guard refreshed,
                      self.tincanAccess == .ready,
                      let inbox = self.tincanInbox,
                      inbox.status == .ready,
                      inbox.enabled else {
                    self.decisionResultMessage = "The Hub acknowledged the decision, but the current task state could not be confirmed. Refresh before taking any further action."
                    return
                }
                if inbox.held.contains(where: { $0.requestID == requestID }) {
                    self.decisionResultMessage = "The Hub acknowledged the decision, but still lists this request as held. Refresh before taking any further action."
                } else {
                    self.decisionResultMessage = decision == .approve
                        ? "Approval accepted. The request is no longer held by the Hub."
                        : "Denial accepted. The request is no longer held by the Hub."
                }
            } catch is CancellationError {
                return
            } catch let error as HubIslandAPIError {
                guard !Task.isCancelled else { return }
                if error == .decisionConflict || error == .operatorPermissionRequired || error == .unauthorized {
                    self.blockedDecisionRequestIDs.insert(requestID)
                }
                self.showTincan(error)
                self.decisionResultMessage = error == .decisionConflict
                    ? "This request is stale or no longer held. No retry was sent; refresh and inspect its current state."
                    : error.localizedDescription
                _ = await self.loadTincanInbox(waitForInFlight: true)
            } catch {
                guard !Task.isCancelled else { return }
                self.blockedDecisionRequestIDs.insert(requestID)
                self.tincanAccess = .error
                self.decisionResultMessage = "The result is uncertain. The app will not retry this decision; refresh the task list and verify the Hub state."
                _ = await self.loadTincanInbox(waitForInFlight: true)
            }
        }
    }

    private func runOperatorAction(_ action: @escaping @MainActor () async -> Void) {
        guard operatorActionTask == nil else { return }
        let id = UUID()
        operatorActionID = id
        operatorActionTask = Task { [weak self] in
            guard let self else { return }
            await action()
            guard self.operatorActionID == id else { return }
            self.operatorActionTask = nil
            self.operatorActionID = nil
        }
    }

    private func currentTincanTask(requestID: String) -> HubTincanTraceSummary? {
        tincanInbox?.held.first(where: { $0.requestID == requestID })
            ?? tincanInbox?.traces.first(where: { $0.requestID == requestID })
    }

    private func operatorAuthorizationCredential() async throws -> String? {
        if !operatorCredentialLoaded || operatorCredential == nil {
            let loaded = try await loadCredential()
            try Task.checkCancellation()
            operatorCredential = loaded
            credential = loaded
            credentialAvailable = loaded != nil
            operatorCredentialLoaded = loaded != nil
        }
        return operatorCredential
    }

    private func loadTincanInbox(waitForInFlight: Bool = false) async -> Bool {
        if isRefreshingTincan {
            guard waitForInFlight else { return false }
            for _ in 0..<250 {
                guard !Task.isCancelled else { return false }
                if !isRefreshingTincan { break }
                do {
                    try await Task.sleep(for: .milliseconds(20))
                } catch {
                    return false
                }
            }
            guard !isRefreshingTincan, !Task.isCancelled else { return false }
            return await loadTincanInbox()
        }
        isRefreshingTincan = true
        defer { isRefreshingTincan = false }
        do {
            guard let credential = try await operatorAuthorizationCredential() else {
                guard !Task.isCancelled else { return false }
                tincanAccess = .needsCredential
                tincanInbox = nil
                tincanErrorMessage = nil
                return false
            }
            let loaded = try await api.tincanInbox(credential: credential)
            try Task.checkCancellation()
            tincanInbox = loaded
            tincanAccess = .ready
            tincanErrorMessage = nil

            if loaded.status == .ready && loaded.enabled {
                if hasTincanBaseline {
                    let newEntries = loaded.held.filter { !knownHeldRequestIDs.contains($0.requestID) }
                    if !newEntries.isEmpty { onNewHeldRequests?(newEntries) }
                } else {
                    hasTincanBaseline = true
                }
                rememberHeldRequestIDs(loaded.held)
            }

            if let selectedTincanTask,
               let latest = currentTincanTask(requestID: selectedTincanTask.requestID) {
                self.selectedTincanTask = latest
            }
            return true
        } catch is CancellationError {
            return false
        } catch let error as HubIslandAPIError {
            guard !Task.isCancelled else { return false }
            showTincan(error)
            return false
        } catch {
            guard !Task.isCancelled else { return false }
            tincanAccess = .error
            tincanInbox = nil
            tincanErrorMessage = "Could not read Tincan task metadata from the local Hub."
            return false
        }
    }

    private func rememberHeldRequestIDs(_ entries: [HubTincanTraceSummary]) {
        for requestID in entries.map(\.requestID) where !requestID.isEmpty {
            if knownHeldRequestIDs.insert(requestID).inserted {
                knownHeldRequestIDOrder.append(requestID)
            }
        }
        while knownHeldRequestIDOrder.count > rememberedHeldRequestLimit {
            knownHeldRequestIDs.remove(knownHeldRequestIDOrder.removeFirst())
        }
    }

    private func showTincan(_ error: HubIslandAPIError) {
        tincanErrorMessage = error.localizedDescription
        switch error {
        case .operatorPermissionRequired:
            // A legacy app credential can still read snapshots; do not treat this
            // as pairing or fall back to another credential.
            operatorCredentialLoaded = false
            tincanAccess = .permissionRequired
            tincanInbox = nil
        case .unauthorized:
            operatorCredentialLoaded = false
            tincanAccess = .unauthorized
            tincanInbox = nil
        case .unreachable:
            tincanAccess = .offline
            tincanInbox = nil
        default:
            tincanAccess = .error
            tincanInbox = nil
        }
    }

    /// Cancels panel-scoped actions. Background metadata polling continues while hidden.
    func panelHidden() {
        detailVisibilityGeneration = UUID()
        operationTask?.cancel()
        operationTask = nil
        operationID = nil
        operatorActionTask?.cancel()
        operatorActionTask = nil
        operatorActionID = nil
        isReadingTincanTrace = false
        if activeDecisionRequestID != nil {
            decisionResultMessage = "Decision interrupted. Refresh the task list to verify the Hub state before taking another action."
        }
        activeDecisionRequestID = nil
        isBusy = false
        busyProviders.removeAll()
        if connection == .checking { connection = connectionBeforeRefresh }
    }

    func beginPairing() {
        run { [weak self] in await self?.requestPairing() }
    }

    func checkPairingApproval() {
        run { [weak self] in await self?.claimPairing() }
    }

    func setEnabled(_ provider: HubProvider, enabled: Bool) {
        guard operationTask == nil,
              !busyProviders.contains(provider.id),
              let credential,
              let snapshot else { return }
        busyProviders.insert(provider.id)
        run(allowProviderWork: true) { [weak self] in
            guard let self else { return }
            defer { if !Task.isCancelled { self.busyProviders.remove(provider.id) } }
            await self.apply(HubToolUpdate(revision: snapshot.revision, provider: provider.id, enabled: enabled), credential: credential)
        }
    }

    func selectAccount(_ account: String, for provider: HubProvider) {
        guard operationTask == nil,
              provider.selectableAccounts.contains(account),
              provider.account != account,
              !busyProviders.contains(provider.id),
              let credential,
              let snapshot else { return }
        busyProviders.insert(provider.id)
        run(allowProviderWork: true) { [weak self] in
            guard let self else { return }
            defer { if !Task.isCancelled { self.busyProviders.remove(provider.id) } }
            await self.apply(HubToolUpdate(revision: snapshot.revision, provider: provider.id, account: account), credential: credential)
        }
    }

    func removePairingFromThisMac() {
        run { [weak self] in
            guard let self else { return }
            self.isBusy = true
            defer { self.isBusy = false }
            do {
                try await Self.deleteCredentialFromKeychain()
                self.credential = nil
                self.operatorCredential = nil
                self.operatorCredentialLoaded = false
                self.credentialAvailable = false
                self.snapshot = nil
                self.pairing = nil
                self.connection = .unpaired
                self.errorMessage = nil
                self.tincanInbox = nil
                self.tincanAccess = .needsCredential
            } catch {
                self.errorMessage = "Could not remove the Hub Island credential from Keychain."
            }
        }
    }

    private func run(allowProviderWork: Bool = false, _ operation: @escaping @MainActor () async -> Void) {
        guard operationTask == nil, allowProviderWork || busyProviders.isEmpty else { return }
        let id = UUID()
        operationID = id
        operationTask = Task { [weak self] in
            guard let self else { return }
            await operation()
            guard self.operationID == id else { return }
            self.operationTask = nil
            self.operationID = nil
        }
    }

    private func loadSnapshot() async {
        isBusy = true
        connectionBeforeRefresh = connection
        connection = .checking
        errorMessage = nil
        defer { if !Task.isCancelled { isBusy = false } }

        do {
            if credential == nil {
                let loaded = try await loadCredential()
                try Task.checkCancellation()
                credential = loaded
                operatorCredential = loaded
                operatorCredentialLoaded = loaded != nil
                credentialAvailable = credential != nil
            }
            guard let credential else {
                connection = pairing == nil ? .unpaired : .awaitingApproval
                snapshot = nil
                return
            }
            let loaded = try await api.snapshot(credential: credential)
            try Task.checkCancellation()
            snapshot = loaded
            connection = .connected
        } catch is CancellationError {
            return
        } catch let error as HubIslandAPIError {
            guard !Task.isCancelled else { return }
            show(error)
        } catch {
            guard !Task.isCancelled else { return }
            connection = .error
            errorMessage = "Could not read the Hub Island credential from Keychain."
        }
    }

    private func requestPairing() async {
        isBusy = true
        errorMessage = nil
        defer { if !Task.isCancelled { isBusy = false } }
        do {
            let request = try await api.requestPairing()
            try Task.checkCancellation()
            pairing = request
            connection = .awaitingApproval
        } catch is CancellationError {
            return
        } catch let error as HubIslandAPIError {
            show(error)
        } catch {
            guard !Task.isCancelled else { return }
            connection = .error
            errorMessage = "Could not start a Hub Island pairing request."
        }
    }

    private func claimPairing() async {
        guard let pairing else { return }
        isBusy = true
        errorMessage = nil
        defer { if !Task.isCancelled { isBusy = false } }
        do {
            let claim = try await api.claimPairing(pairing)
            try Task.checkCancellation()
            switch claim {
            case .pending:
                connection = .awaitingApproval
            case .approved(let approval):
                try await Self.saveCredentialToKeychain(approval.credential)
                try Task.checkCancellation()
                credential = approval.credential
                operatorCredential = approval.credential
                operatorCredentialLoaded = true
                credentialAvailable = true
                self.pairing = nil
                let loaded = try await api.snapshot(credential: approval.credential)
                try Task.checkCancellation()
                snapshot = loaded
                connection = .connected
            }
        } catch is CancellationError {
            return
        } catch let error as HubIslandAPIError {
            guard !Task.isCancelled else { return }
            if error == .pairingExpired { self.pairing = nil }
            show(error)
        } catch {
            guard !Task.isCancelled else { return }
            connection = .error
            errorMessage = "Could not save the approved credential in Keychain."
        }
    }

    private func apply(_ update: HubToolUpdate, credential: String) async {
        isBusy = true
        errorMessage = nil
        defer { if !Task.isCancelled { isBusy = false } }
        do {
            let loaded = try await api.updateTool(credential: credential, update: update)
            try Task.checkCancellation()
            snapshot = loaded
            connection = .connected
        } catch is CancellationError {
            return
        } catch let error as HubIslandAPIError {
            show(error)
        } catch {
            guard !Task.isCancelled else { return }
            connection = .error
            errorMessage = "Could not save the Hub configuration change."
        }
    }

    private func show(_ error: HubIslandAPIError) {
        guard !Task.isCancelled else { return }
        errorMessage = error.localizedDescription
        switch error {
        case .unauthorized:
            connection = .unauthorized
            snapshot = nil
        case .unreachable:
            connection = .offline
            snapshot = nil
        default:
            connection = .error
        }
    }

    private nonisolated static func loadCredentialFromKeychain() async throws -> String? {
        try await Task.detached(priority: .utility) {
            try HubIslandCredentialStore.load()
        }.value
    }

    private nonisolated static func saveCredentialToKeychain(_ credential: String) async throws {
        try await Task.detached(priority: .utility) {
            try HubIslandCredentialStore.save(credential)
        }.value
    }

    private nonisolated static func deleteCredentialFromKeychain() async throws {
        try await Task.detached(priority: .utility) {
            try HubIslandCredentialStore.delete()
        }.value
    }
}
