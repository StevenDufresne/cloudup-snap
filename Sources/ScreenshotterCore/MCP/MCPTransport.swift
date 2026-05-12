import Foundation

public protocol MCPTransport: Sendable {
    func send(
        request: JSONRPCRequest,
        extraHeaders: [String: String]
    ) async throws -> JSONRPCResponse
}
