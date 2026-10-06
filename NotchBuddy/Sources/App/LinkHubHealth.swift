import Combine
import Foundation

enum LinkHubHealthStatus: Equatable {
    case notChecked
    case checking
    case authenticationRequired
    case ready(upstreamsVerified: Bool)
    case httpError(Int)
    case unexpectedResponse
    case unreachable
}

enum LinkHubHealthEndpoint {
    static let url = URL(string: "http://127.0.0.1:8767/healthz")!

    static func classify(statusCode: Int, body: Data?) -> LinkHubHealthStatus {
        guard statusCode != 401 else { return .authenticationRequired }
        guard statusCode == 200,
              let body,
              let payload = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              payload["status"] as? String == "ready",
              payload["service"] as? String == "agent-linkhub",
              let upstreamsVerified = payload["upstreams_verified"] as? Bool else {
            return statusCode == 200 ? .unexpectedResponse : .httpError(statusCode)
        }
        return .ready(upstreamsVerified: upstreamsVerified)
    }
}

@MainActor
final class LinkHubHealthMonitor: ObservableObject {
    @Published private(set) var status: LinkHubHealthStatus = .notChecked

    func refresh() async {
        guard status != .checking else { return }
        status = .checking

        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil

        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: LinkHubHealthEndpoint.url)
        request.httpMethod = "GET"
        request.timeoutInterval = 3
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")

        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                status = .unreachable
                return
            }
            status = LinkHubHealthEndpoint.classify(statusCode: response.statusCode, body: data)
        } catch {
            status = .unreachable
        }
    }
}
