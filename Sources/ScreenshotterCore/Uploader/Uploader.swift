import Foundation

public struct Uploader: Sendable {
    public let mcp: MCPClient
    public let payment: PaymentClient

    public init(mcp: MCPClient, payment: PaymentClient) {
        self.mcp = mcp
        self.payment = payment
    }

    public func upload(data: Data, filename: String, mime: String) async throws -> URL {
        let args: [String: EIP712Value] = [
            "filename": .string(filename),
            "mime": .string(mime),
            "content_base64": .string(data.base64EncodedString()),
        ]
        do {
            let result = try await mcp.callTool(name: "quick_upload", arguments: args)
            return try extractShareURL(from: result)
        } catch let err as JSONRPCError where payment.isPaymentRequired(err) {
            let payload = try payment.extractPayload(from: err)
            guard let challenge = payload.challenges.first else {
                throw PaymentError.malformedChallenge("empty challenges array")
            }
            let credential = try await payment.settle(challenge: challenge)
            let result = try await mcp.callTool(
                name: "quick_upload",
                arguments: args,
                meta: ["org.paymentauth/credential": credential.asEIP712Value]
            )
            return try extractShareURL(from: result)
        }
    }

    private func extractShareURL(from value: EIP712Value) throws -> URL {
        guard case .object(let obj) = value else {
            throw PaymentError.other("response was not an object")
        }
        // MCP tools/call wraps the tool's actual result in a `content` array,
        // typically `[{type: "text", text: "<json>"}]`. Parse the inner text as JSON
        // if we see that shape; otherwise look for share_url directly.
        if case .array(let content) = obj["content"] ?? .null {
            for item in content {
                if case .object(let part) = item,
                   case .string(let text) = part["text"] ?? .null,
                   let data = text.data(using: .utf8),
                   let inner = try? JSONDecoder().decode(EIP712Value.self, from: data),
                   case .object(let innerObj) = inner,
                   case .string(let s) = innerObj["share_url"] ?? .null,
                   let url = URL(string: s) {
                    return url
                }
            }
            throw PaymentError.other("MCP content array had no share_url text part")
        }
        if case .string(let s) = obj["share_url"] ?? .null, let url = URL(string: s) {
            return url
        }
        throw PaymentError.other("response missing share_url")
    }
}
