import Foundation

public struct MCPSendResult: Sendable {
    public let response: JSONRPCResponse
    public let responseHeaders: [String: String]
    public init(response: JSONRPCResponse, responseHeaders: [String: String] = [:]) {
        self.response = response
        self.responseHeaders = responseHeaders
    }
}

public protocol MCPTransport: Sendable {
    func send(
        request: JSONRPCRequest,
        extraHeaders: [String: String]
    ) async throws -> MCPSendResult
}
