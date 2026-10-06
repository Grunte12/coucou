import Foundation

@main
enum LinkHubHealthTests {
    static func main() {
        precondition(LinkHubHealthEndpoint.url.absoluteString == "http://127.0.0.1:8767/healthz")

        precondition(
            LinkHubHealthEndpoint.classify(statusCode: 401, body: nil) == .authenticationRequired
        )

        let ready = #"{"status":"ready","service":"agent-linkhub","upstreams_verified":false}"#.data(using: .utf8)!
        precondition(
            LinkHubHealthEndpoint.classify(statusCode: 200, body: ready) == .ready(upstreamsVerified: false)
        )

        let verified = #"{"status":"ready","service":"agent-linkhub","upstreams_verified":true}"#.data(using: .utf8)!
        precondition(
            LinkHubHealthEndpoint.classify(statusCode: 200, body: verified) == .ready(upstreamsVerified: true)
        )

        precondition(
            LinkHubHealthEndpoint.classify(statusCode: 200, body: Data("{}".utf8)) == .unexpectedResponse
        )
        precondition(LinkHubHealthEndpoint.classify(statusCode: 503, body: nil) == .httpError(503))

        print("LinkHub health classification: 6 cases passed")
    }
}
