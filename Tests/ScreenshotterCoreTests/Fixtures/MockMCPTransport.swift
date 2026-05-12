import Foundation
@testable import ScreenshotterCore

final class MockMCPTransport: MCPTransport, @unchecked Sendable {
    private(set) var receivedRequests: [(request: JSONRPCRequest, headers: [String: String])] = []
    var queuedResponses: [JSONRPCResponse] = []

    func send(
        request: JSONRPCRequest,
        extraHeaders: [String: String]
    ) async throws -> JSONRPCResponse {
        receivedRequests.append((request, extraHeaders))
        guard !queuedResponses.isEmpty else { fatalError("no queued response") }
        return queuedResponses.removeFirst()
    }
}
