import Foundation
import Security

enum HubIslandEndpoint {
    static let origin = URL(string: "http://127.0.0.1:8768")!
    static let console = URL(string: "http://127.0.0.1:8768/")!

    static func url(_ path: String) -> URL {
        origin.appending(path: path)
    }
}

enum HubIslandAPIError: Error, LocalizedError, Equatable, Sendable {
    case unauthorized
    case operatorPermissionRequired
    case revisionConflict
    case decisionConflict
    case pairingExpired
    case httpStatus(Int)
    case invalidResponse
    case unreachable

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "This Hub Island pairing is no longer authorized. Pair again in the Manager Console."
        case .operatorPermissionRequired:
            return "This Hub Island credential needs operator permission. Reconnect it with Tincan approval enabled in the trusted installer."
        case .revisionConflict:
            return "The Hub configuration changed elsewhere. Refresh, then retry your change."
        case .decisionConflict:
            return "This request is no longer held. Refresh the task list; no decision was retried."
        case .pairingExpired:
            return "This pairing request expired. Start a new request."
        case .httpStatus(let code):
            return "The local Hub returned HTTP \(code)."
        case .invalidResponse:
            return "The local Hub returned an unexpected response."
        case .unreachable:
            return "The local Hub is not reachable at 127.0.0.1:8768."
        }
    }
}

struct HubPairingRequest: Decodable, Sendable {
    let requestId: String
    let pollSecret: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case pollSecret = "poll_secret"
        case expiresIn = "expires_in"
    }

    var isUsable: Bool {
        !requestId.isEmpty && !pollSecret.isEmpty && expiresIn > 0
    }
}

struct HubPairingApproval: Decodable, Sendable {
    let credential: String
    let expiresAt: String

    enum CodingKeys: String, CodingKey {
        case credential
        case expiresAt = "expires_at"
    }
}

enum HubPairingClaim: Sendable {
    case pending
    case approved(HubPairingApproval)
}

struct HubSnapshot: Decodable, Equatable, Sendable {
    let revision: Int
    let hub: HubServiceHealth
    let providers: [HubProvider]
    let jobs: [HubJob]
}

struct HubServiceHealth: Decodable, Equatable, Sendable {
    let status: String
}

struct HubProvider: Decodable, Equatable, Identifiable, Sendable {
    let id: String
    let enabled: Bool
    let account: String?
    let selectableAccounts: [String]
    let health: HubProviderHealth

    enum CodingKeys: String, CodingKey {
        case id, enabled, account, health
        case selectableAccounts = "selectable_accounts"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        enabled = try values.decode(Bool.self, forKey: .enabled)
        account = try values.decodeIfPresent(String.self, forKey: .account)
        selectableAccounts = try values.decodeIfPresent([String].self, forKey: .selectableAccounts) ?? []
        health = try values.decode(HubProviderHealth.self, forKey: .health)
    }
}

struct HubProviderHealth: Decodable, Equatable, Sendable {
    let status: String
}

struct HubJob: Decodable, Equatable, Identifiable, Sendable {
    let id: String
    let provider: String
    let capability: String
    let state: String
    let createdAt: String
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, provider, capability, state
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

enum HubTincanStatus: String, Decodable, Equatable, Sendable {
    case ready
    case disabled
    case unavailable
}

struct HubTincanTraceSummary: Decodable, Equatable, Identifiable, Sendable {
    let id: String
    let requestID: String
    let traceID: String
    let sender: String
    let recipient: String
    let state: String
    let title: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, state, title
        case requestID = "request_id"
        case traceID = "trace_id"
        case sender = "from"
        case recipient = "to"
        case createdAt = "created_at"
    }
}

struct HubTincanAgent: Decodable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let online: Bool
    let kind: String?
    let wake: String?
    let version: String?
    let lastActive: String?
    let queued: Int
    let claimed: Int

    enum CodingKeys: String, CodingKey {
        case id, name, online, kind, wake, version, queued, claimed
        case lastActive = "last_active"
    }
}

struct HubTincanRoster: Decodable, Equatable, Sendable {
    let status: HubTincanStatus
    let enabled: Bool
    let agents: [HubTincanAgent]
}

struct HubTincanInbox: Decodable, Equatable, Sendable {
    let status: HubTincanStatus
    let enabled: Bool
    let heldCount: Int
    let heldTruncated: Bool
    let traces: [HubTincanTraceSummary]
    let held: [HubTincanTraceSummary]

    enum CodingKeys: String, CodingKey {
        case status, enabled, traces, held
        case heldCount = "held_count"
        case heldTruncated = "held_truncated"
    }
}

struct HubTincanTrace: Decodable, Equatable, Sendable {
    let traceID: String
    let steps: [HubTincanStep]
    let events: [HubTincanEvent]

    enum CodingKeys: String, CodingKey {
        case steps, events
        case traceID = "trace_id"
    }
}

struct HubTincanStep: Decodable, Equatable, Sendable, Identifiable {
    let id: String
    let sender: String
    let recipient: String
    let state: String
    let kind: String
    let body: String
    let createdAt: String
    let reply: HubTincanReply?
    let exchanges: [HubTincanExchange]
    let progress: HubTincanProgress?

    enum CodingKeys: String, CodingKey {
        case id, state, kind, body, reply, exchanges, progress
        case sender = "from"
        case recipient = "to"
        case createdAt = "created_at"
    }
}

struct HubTincanReply: Decodable, Equatable, Sendable {
    let sender: String
    let status: String
    let body: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case sender = "from"
        case status, body
        case createdAt = "created_at"
    }
}

struct HubTincanExchange: Decodable, Equatable, Sendable, Identifiable {
    let question: String
    let answer: String
    let at: String
    var id: String { at + question }

    enum CodingKeys: String, CodingKey { case question, answer, at }

    init(question: String, answer: String, at: String) {
        self.question = question
        self.answer = answer
        self.at = at
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        question = try values.decode(String.self, forKey: .question)
        // Unanswered clarification legitimately has a null answer upstream.
        // Keep it empty, not invented content or permission to act.
        answer = try values.decodeIfPresent(String.self, forKey: .answer) ?? ""
        at = try values.decode(String.self, forKey: .at)
    }
}

struct HubTincanProgress: Decodable, Equatable, Sendable {
    let note: String
    let at: String
    let by: String
}

struct HubTincanEvent: Decodable, Equatable, Sendable, Identifiable {
    let sequence: Int
    let event: String
    let actor: String
    let requestID: String?
    let at: String
    var id: Int { sequence }

    enum CodingKeys: String, CodingKey {
        case event, actor, at
        case sequence = "seq"
        case requestID = "request_id"
    }
}

enum HubTincanDecision: String, Encodable, Decodable, Equatable, Sendable {
    case approve
    case deny
}

struct HubTincanDecisionAcknowledgement: Decodable, Equatable, Sendable {
    let requestID: String
    let decision: HubTincanDecision
    let status: String

    enum CodingKeys: String, CodingKey {
        case decision, status
        case requestID = "request_id"
    }
}

struct HubToolUpdate: Encodable, Sendable {
    let revision: Int
    let provider: String
    let enabled: Bool?
    let account: String?

    init(revision: Int, provider: String, enabled: Bool? = nil, account: String? = nil) {
        self.revision = revision
        self.provider = provider
        self.enabled = enabled
        self.account = account
    }
}

private final class HubRedirectBlocker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // Never follow a redirect carrying the app credential or a pairing secret.
        completionHandler(nil)
    }
}

protocol HubIslandAPI: Sendable {
    func requestPairing() async throws -> HubPairingRequest
    func claimPairing(_ pairing: HubPairingRequest) async throws -> HubPairingClaim
    func snapshot(credential: String) async throws -> HubSnapshot
    func updateTool(credential: String, update: HubToolUpdate) async throws -> HubSnapshot
    func tincanInbox(credential: String) async throws -> HubTincanInbox
    func tincanRoster(credential: String) async throws -> HubTincanRoster
    func tincanTrace(credential: String, traceID: String) async throws -> HubTincanTrace
    func decideTincanRequest(credential: String, requestID: String,
                             decision: HubTincanDecision) async throws -> HubTincanDecisionAcknowledgement
}

extension HubIslandAPI {
    func tincanRoster(credential: String) async throws -> HubTincanRoster {
        throw HubIslandAPIError.invalidResponse
    }

    func tincanInbox(credential: String) async throws -> HubTincanInbox {
        throw HubIslandAPIError.invalidResponse
    }

    func tincanTrace(credential: String, traceID: String) async throws -> HubTincanTrace {
        throw HubIslandAPIError.invalidResponse
    }

    func decideTincanRequest(credential: String, requestID: String,
                             decision: HubTincanDecision) async throws -> HubTincanDecisionAcknowledgement {
        throw HubIslandAPIError.invalidResponse
    }
}

final class HubIslandAPIClient: HubIslandAPI, @unchecked Sendable {
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil

        session = URLSession(configuration: configuration, delegate: HubRedirectBlocker(), delegateQueue: nil)
        encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys]
        decoder = JSONDecoder()
    }

    func requestPairing() async throws -> HubPairingRequest {
        let (data, response) = try await send(path: "/api/island/pair/request", method: "POST")
        try requireSuccess(response)
        let request = try decode(HubPairingRequest.self, from: data)
        guard request.isUsable else { throw HubIslandAPIError.invalidResponse }
        return request
    }

    func claimPairing(_ pairing: HubPairingRequest) async throws -> HubPairingClaim {
        let body = HubPairingClaimBody(requestId: pairing.requestId, pollSecret: pairing.pollSecret)
        let (data, response) = try await send(
            path: "/api/island/pair/claim",
            method: "POST",
            body: try encoder.encode(body)
        )
        if response.statusCode == 202 { return .pending }
        if response.statusCode == 410 { throw HubIslandAPIError.pairingExpired }
        try requireSuccess(response)
        let approval = try decode(HubPairingApproval.self, from: data)
        guard !approval.credential.isEmpty else { throw HubIslandAPIError.invalidResponse }
        return .approved(approval)
    }

    func snapshot(credential: String) async throws -> HubSnapshot {
        let (data, response) = try await send(path: "/api/island/snapshot", method: "GET", credential: credential)
        try requireSuccess(response)
        return try decode(HubSnapshot.self, from: data)
    }

    func updateTool(credential: String, update: HubToolUpdate) async throws -> HubSnapshot {
        let (data, response) = try await send(
            path: "/api/island/tool",
            method: "PUT",
            credential: credential,
            body: try encoder.encode(update)
        )
        try requireSuccess(response)
        return try decode(HubSnapshot.self, from: data)
    }

    func tincanInbox(credential: String) async throws -> HubTincanInbox {
        let (data, response) = try await send(path: "/api/island/tincan", method: "GET", credential: credential)
        try requireOperatorSuccess(response)
        return try decode(HubTincanInbox.self, from: data)
    }

    func tincanRoster(credential: String) async throws -> HubTincanRoster {
        let (data, response) = try await send(path: "/api/island/tincan/agents", method: "GET", credential: credential)
        try requireOperatorSuccess(response)
        let roster = try decode(HubTincanRoster.self, from: data)
        guard roster.agents.count <= 128,
              Set(roster.agents.map(\.id)).count == roster.agents.count,
              roster.agents.allSatisfy({ !$0.id.isEmpty && $0.id == $0.name && $0.queued >= 0 && $0.claimed >= 0 }) else {
            throw HubIslandAPIError.invalidResponse
        }
        return roster
    }

    func tincanTrace(credential: String, traceID: String) async throws -> HubTincanTrace {
        guard !traceID.isEmpty, traceID.utf8.count <= 256,
              let segment = traceID.addingPercentEncoding(
                withAllowedCharacters: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")) else {
            throw HubIslandAPIError.invalidResponse
        }
        let (data, response) = try await send(
            path: "/api/island/tincan/trace/\(segment)", method: "GET", credential: credential
        )
        try requireOperatorSuccess(response)
        return try decode(HubTincanTrace.self, from: data)
    }

    func decideTincanRequest(credential: String, requestID: String,
                             decision: HubTincanDecision) async throws -> HubTincanDecisionAcknowledgement {
        guard !requestID.isEmpty, requestID.utf8.count <= 128 else {
            throw HubIslandAPIError.invalidResponse
        }
        let body = HubTincanDecisionBody(requestID: requestID, decision: decision)
        let (data, response) = try await send(
            path: "/api/island/tincan/decision",
            method: "POST",
            credential: credential,
            body: try encoder.encode(body)
        )
        try requireOperatorSuccess(response)
        let acknowledgement = try decode(HubTincanDecisionAcknowledgement.self, from: data)
        guard acknowledgement.requestID == requestID,
              acknowledgement.decision == decision,
              acknowledgement.status == "completed" else {
            throw HubIslandAPIError.invalidResponse
        }
        return acknowledgement
    }

    private func send(
        path: String,
        method: String,
        credential: String? = nil,
        body: Data? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        let url = HubIslandEndpoint.url(path)
        guard url.scheme == "http", url.host == "127.0.0.1", url.port == 8768 else {
            throw HubIslandAPIError.invalidResponse
        }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
        request.httpMethod = method
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue(HubIslandEndpoint.origin.absoluteString, forHTTPHeaderField: "Origin")
        if let credential {
            guard !credential.isEmpty else { throw HubIslandAPIError.unauthorized }
            request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  http.url?.scheme == "http",
                  http.url?.host == "127.0.0.1",
                  http.url?.port == 8768 else {
                throw HubIslandAPIError.invalidResponse
            }
            return (data, http)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as HubIslandAPIError {
            throw error
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            throw HubIslandAPIError.unreachable
        }
    }

    private func requireSuccess(_ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200..<300:
            return
        case 401:
            throw HubIslandAPIError.unauthorized
        case 409:
            throw HubIslandAPIError.revisionConflict
        case 410:
            throw HubIslandAPIError.pairingExpired
        default:
            throw HubIslandAPIError.httpStatus(response.statusCode)
        }
    }

    private func requireOperatorSuccess(_ response: HTTPURLResponse) throws {
        if response.statusCode == 403 { throw HubIslandAPIError.operatorPermissionRequired }
        if response.statusCode == 409 { throw HubIslandAPIError.decisionConflict }
        try requireSuccess(response)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw HubIslandAPIError.invalidResponse
        }
    }
}

struct HubPairingClaimBody: Encodable, Sendable {
    let requestId: String
    let pollSecret: String
}

struct HubTincanDecisionBody: Encodable, Sendable {
    let requestID: String
    let decision: HubTincanDecision
}

enum HubIslandCredentialError: Error, Equatable, Sendable {
    case readFailed
    case saveFailed
    case deleteFailed
}

enum HubIslandCredentialStore {
    private static let service = "com.hubisland.desktop"
    private static let account = "approved-app-credential"

    static func load() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw HubIslandCredentialError.readFailed
        }
        return value
    }

    static func save(_ credential: String) throws {
        guard let data = credential.data(using: .utf8), !credential.isEmpty else {
            throw HubIslandCredentialError.saveFailed
        }

        let query = baseQuery
        let update: [String: Any] = [kSecValueData as String: data]
        var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            item[kSecAttrSynchronizable as String] = kCFBooleanFalse!
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw HubIslandCredentialError.saveFailed }
    }

    static func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw HubIslandCredentialError.deleteFailed
        }
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse!,
        ]
    }
}
