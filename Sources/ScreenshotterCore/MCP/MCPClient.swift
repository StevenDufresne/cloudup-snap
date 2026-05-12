import Foundation

public actor MCPClient {
    public let transport: MCPTransport
    private var nextId = 1

    public init(transport: MCPTransport) {
        self.transport = transport
    }

    public func callTool(
        name: String,
        arguments: [String: EIP712Value],
        meta: [String: EIP712Value]? = nil,
        extraHeaders: [String: String] = [:]
    ) async throws -> EIP712Value {
        let id = nextId; nextId += 1
        var params: [String: EIP712Value] = [
            "name": .string(name),
            "arguments": .object(arguments),
        ]
        if let meta = meta, !meta.isEmpty {
            params["_meta"] = .object(meta)
        }
        let req = JSONRPCRequest(id: .number(id), method: "tools/call", params: params)
        let resp = try await transport.send(request: req, extraHeaders: extraHeaders)
        switch resp.outcome {
        case .success(let v): return v
        case .failure(let err): throw err
        }
    }
}
