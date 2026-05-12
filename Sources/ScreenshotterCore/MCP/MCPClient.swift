import Foundation

public actor MCPClient {
    public let transport: MCPTransport
    private var nextId = 1
    private var sessionId: String?
    private var didInitialize = false

    public let clientName: String
    public let clientVersion: String
    public let protocolVersion: String

    public init(
        transport: MCPTransport,
        clientName: String = "screenshotter-cli",
        clientVersion: String = "0.1.0",
        protocolVersion: String = "2025-06-18"
    ) {
        self.transport = transport
        self.clientName = clientName
        self.clientVersion = clientVersion
        self.protocolVersion = protocolVersion
    }

    /// Send `initialize`, capture the `Mcp-Session-Id` header, send `notifications/initialized`,
    /// and mark the client as ready. Idempotent.
    public func initializeIfNeeded() async throws {
        if didInitialize { return }
        let id = nextId; nextId += 1
        let params: [String: EIP712Value] = [
            "protocolVersion": .string(protocolVersion),
            "capabilities": .object([:]),
            "clientInfo": .object([
                "name": .string(clientName),
                "version": .string(clientVersion),
            ]),
        ]
        let req = JSONRPCRequest(id: .number(id), method: "initialize", params: params)
        let result = try await transport.send(request: req, extraHeaders: [:])
        // The session id header is case-insensitive; HTTPURLResponse normalizes but be defensive.
        let sid = result.responseHeaders.first(where: { $0.key.lowercased() == "mcp-session-id" })?.value
        self.sessionId = sid
        if case .failure(let err) = result.response.outcome { throw err }
        // Spec requires a `notifications/initialized` after a successful initialize. The
        // server treats it as a notification (no response expected); we still POST it for
        // protocol compliance. Note JSON-RPC notifications have no `id`, but our envelope
        // requires one — we send it with a dummy id, which servers tolerate.
        let initialized = JSONRPCRequest(
            id: .number(nextId), method: "notifications/initialized", params: [:]
        )
        nextId += 1
        _ = try? await transport.send(request: initialized, extraHeaders: sessionHeaders())
        didInitialize = true
    }

    public func callTool(
        name: String,
        arguments: [String: EIP712Value],
        meta: [String: EIP712Value]? = nil,
        extraHeaders: [String: String] = [:]
    ) async throws -> EIP712Value {
        try await initializeIfNeeded()
        let id = nextId; nextId += 1
        var params: [String: EIP712Value] = [
            "name": .string(name),
            "arguments": .object(arguments),
        ]
        if let meta = meta, !meta.isEmpty {
            params["_meta"] = .object(meta)
        }
        let req = JSONRPCRequest(id: .number(id), method: "tools/call", params: params)
        var headers = sessionHeaders()
        for (k, v) in extraHeaders { headers[k] = v }
        let result = try await transport.send(request: req, extraHeaders: headers)
        switch result.response.outcome {
        case .success(let v): return v
        case .failure(let err): throw err
        }
    }

    private func sessionHeaders() -> [String: String] {
        guard let sid = sessionId else { return [:] }
        return ["Mcp-Session-Id": sid]
    }
}
