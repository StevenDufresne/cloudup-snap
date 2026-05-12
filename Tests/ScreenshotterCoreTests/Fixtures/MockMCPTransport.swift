import Foundation
@testable import ScreenshotterCore

final class MockMCPTransport: MCPTransport, @unchecked Sendable {
    private(set) var receivedRequests: [(request: JSONRPCRequest, headers: [String: String])] = []
    var queuedResponses: [JSONRPCResponse] = []
    var queuedHeaders: [[String: String]] = []
    /// If true (default), `MCPClient.initializeIfNeeded()` is satisfied transparently —
    /// the mock auto-queues a fake initialize response so unit tests don't have to.
    var autoSatisfyInitialize: Bool = true

    func send(
        request: JSONRPCRequest,
        extraHeaders: [String: String]
    ) async throws -> MCPSendResult {
        // Auto-satisfy initialize + notifications/initialized so unit tests can focus on
        // tools/call. These auto-handled requests are NOT appended to receivedRequests so
        // existing assertions about call count still apply at the tool-call level.
        if autoSatisfyInitialize {
            if request.method == "initialize" {
                let body = #"{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-06-18","capabilities":{},"serverInfo":{"name":"mock","version":"0"}}}"#
                let resp = try JSONDecoder().decode(JSONRPCResponse.self, from: body.data(using: .utf8)!)
                return MCPSendResult(response: resp, responseHeaders: ["Mcp-Session-Id": "mock-session"])
            }
            if request.method == "notifications/initialized" {
                let body = #"{"jsonrpc":"2.0","id":1,"result":null}"#
                let resp = try JSONDecoder().decode(JSONRPCResponse.self, from: body.data(using: .utf8)!)
                return MCPSendResult(response: resp)
            }
        }

        receivedRequests.append((request, extraHeaders))
        guard !queuedResponses.isEmpty else { fatalError("no queued response for \(request.method)") }
        let resp = queuedResponses.removeFirst()
        let hdrs = queuedHeaders.isEmpty ? [:] : queuedHeaders.removeFirst()
        return MCPSendResult(response: resp, responseHeaders: hdrs)
    }
}
