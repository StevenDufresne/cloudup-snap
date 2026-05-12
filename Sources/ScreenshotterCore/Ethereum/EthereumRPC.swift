import Foundation

/// Ethereum JSON-RPC "quantity" type: 0x-prefixed hex, no leading zeros except for "0x0".
public struct HexQuantity: Codable, Equatable, Sendable {
    public let hexString: String

    public init(uint64 value: UInt64) {
        self.hexString = "0x" + String(value, radix: 16)
    }

    public init(hex: String) throws {
        var s = hex
        if s.hasPrefix("0x") { s = String(s.dropFirst(2)) }
        if s.isEmpty { s = "0" }
        guard UInt64(s, radix: 16) != nil else {
            throw NSError(domain: "HexQuantity", code: 1, userInfo: [NSLocalizedDescriptionKey: "invalid hex quantity: \(hex)"])
        }
        self.hexString = "0x" + s
    }

    public var uint64: UInt64 {
        let s = hexString.hasPrefix("0x") ? String(hexString.dropFirst(2)) : hexString
        return UInt64(s, radix: 16) ?? 0
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        try self.init(hex: try c.decode(String.self))
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(hexString)
    }
}

public struct TransactionReceipt: Codable, Sendable {
    public let transactionHash: String
    public let blockNumber: String?
    public let status: String?
    public var didSucceed: Bool { status == "0x1" }
}

public protocol EthereumRPC: Sendable {
    func call<T: Decodable>(_ method: String, params: [Any]) async throws -> T
}

public struct HTTPEthereumRPC: EthereumRPC {
    public let endpoint: URL
    public let session: URLSession

    public init(endpoint: URL, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.session = session
    }

    public func call<T: Decodable>(_ method: String, params: [Any]) async throws -> T {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let envelope: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": method,
            "params": params,
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: envelope)
        let (data, _) = try await session.data(for: req)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let err = json?["error"] as? [String: Any] {
            let msg = (err["message"] as? String) ?? "unknown RPC error"
            throw NSError(domain: "HTTPEthereumRPC", code: (err["code"] as? Int) ?? -1, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        guard let result = json?["result"] else {
            throw NSError(domain: "HTTPEthereumRPC", code: -2, userInfo: [NSLocalizedDescriptionKey: "missing result"])
        }
        let resultData = try JSONSerialization.data(withJSONObject: result, options: .fragmentsAllowed)
        return try JSONDecoder().decode(T.self, from: resultData)
    }
}

// MARK: Higher-level helpers used by Wallet

public extension EthereumRPC {
    func chainId() async throws -> UInt64 {
        let q: HexQuantity = try await call("eth_chainId", params: [])
        return q.uint64
    }
    func transactionCount(address: EthereumAddress, block: String = "pending") async throws -> UInt64 {
        let q: HexQuantity = try await call("eth_getTransactionCount", params: [address.hexString(), block])
        return q.uint64
    }
    func maxPriorityFeePerGas() async throws -> UInt64 {
        let q: HexQuantity = try await call("eth_maxPriorityFeePerGas", params: [])
        return q.uint64
    }
    func gasPrice() async throws -> UInt64 {
        let q: HexQuantity = try await call("eth_gasPrice", params: [])
        return q.uint64
    }
    func estimateGas(from: EthereumAddress, to: EthereumAddress, data: Data) async throws -> UInt64 {
        let q: HexQuantity = try await call("eth_estimateGas", params: [[
            "from": from.hexString(),
            "to": to.hexString(),
            "data": data.hexEncodedString(prefix: true),
        ]])
        return q.uint64
    }
    func sendRawTransaction(_ raw: Data) async throws -> String {
        let result: String = try await call("eth_sendRawTransaction", params: [raw.hexEncodedString(prefix: true)])
        return result
    }
    /// Returns nil only when the RPC node explicitly reports the receipt isn't ready
    /// (`result: null`). Network / auth / HTTP errors propagate so the caller's poll
    /// loop doesn't silently turn them into a `receiptTimeout`.
    func transactionReceipt(_ txHash: String) async throws -> TransactionReceipt? {
        let raw: EIP712Value = try await call("eth_getTransactionReceipt", params: [txHash])
        if case .null = raw { return nil }
        let json = try JSONEncoder().encode(raw)
        return try JSONDecoder().decode(TransactionReceipt.self, from: json)
    }
}
