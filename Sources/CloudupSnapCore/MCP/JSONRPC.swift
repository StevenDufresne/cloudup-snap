import Foundation

public enum JSONRPCID: Codable, Hashable, Sendable {
    case number(Int)
    case string(String)

    public init(from d: Decoder) throws {
        let c = try d.singleValueContainer()
        if let i = try? c.decode(Int.self) { self = .number(i); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        throw DecodingError.typeMismatch(JSONRPCID.self,
            .init(codingPath: d.codingPath, debugDescription: "id must be int or string"))
    }
    public func encode(to e: Encoder) throws {
        var c = e.singleValueContainer()
        switch self {
        case .number(let i): try c.encode(i)
        case .string(let s): try c.encode(s)
        }
    }
}

/// General JSON value type. Reused by EIP712Value name for historical reasons —
/// this is essentially a JSON value (string, number, bool, object, array, null).
public enum EIP712Value: Codable, Hashable, Sendable {
    case string(String)
    case number(String)   // kept as decimal string to avoid precision loss
    case bool(Bool)
    case object([String: EIP712Value])
    case array([EIP712Value])
    case null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let n = try? c.decode(Double.self) {
            if n.rounded() == n && abs(n) < 1e15 {
                self = .number(String(Int64(n)))
            } else {
                self = .number(String(n))
            }
            return
        }
        if let arr = try? c.decode([EIP712Value].self) { self = .array(arr); return }
        if let dict = try? c.decode([String: EIP712Value].self) { self = .object(dict); return }
        self = .null
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n):
            // Emit as JSON number when representable, else as string fallback.
            if let i = Int64(n) { try c.encode(i) }
            else if let d = Double(n) { try c.encode(d) }
            else { try c.encode(n) }
        case .bool(let b):   try c.encode(b)
        case .object(let o): try c.encode(o)
        case .array(let a):  try c.encode(a)
        case .null:          try c.encodeNil()
        }
    }

    public var stringValue: String? { if case .string(let s) = self { return s } else { return nil } }
    public var objectValue: [String: EIP712Value]? { if case .object(let o) = self { return o } else { return nil } }
}

public struct JSONRPCRequest: Codable, Sendable {
    public let jsonrpc = "2.0"
    /// Nil for JSON-RPC notifications (no response expected, per spec §4.1).
    /// Set for requests that expect a Response.
    public let id: JSONRPCID?
    public let method: String
    public let params: [String: EIP712Value]?

    public init(id: JSONRPCID, method: String, params: [String: EIP712Value]? = nil) {
        self.id = id
        self.method = method
        self.params = params
    }

    /// JSON-RPC notification — encoded without an `id` field. Use this for
    /// methods like `notifications/initialized` that must not carry an id.
    public static func notification(method: String, params: [String: EIP712Value]? = nil) -> JSONRPCRequest {
        JSONRPCRequest(idOverride: nil, method: method, params: params)
    }

    private init(idOverride: JSONRPCID?, method: String, params: [String: EIP712Value]?) {
        self.id = idOverride
        self.method = method
        self.params = params
    }

    enum CodingKeys: String, CodingKey { case jsonrpc, id, method, params }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(jsonrpc, forKey: .jsonrpc)
        try c.encodeIfPresent(id, forKey: .id)
        try c.encode(method, forKey: .method)
        try c.encodeIfPresent(params, forKey: .params)
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(JSONRPCID.self, forKey: .id)
        self.method = try c.decode(String.self, forKey: .method)
        self.params = try c.decodeIfPresent([String: EIP712Value].self, forKey: .params)
    }
}

public struct JSONRPCError: Codable, Error, Sendable {
    public let code: Int
    public let message: String
    public let data: EIP712Value?

    public init(code: Int, message: String, data: EIP712Value? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }

    enum CodingKeys: String, CodingKey { case code, message, data }

    public init(from decoder: Decoder) throws {
        // Spec-compliant shape: {"code": Int, "message": String, "data": …}.
        if let c = try? decoder.container(keyedBy: CodingKeys.self),
           let code = try? c.decode(Int.self, forKey: .code),
           let message = try? c.decode(String.self, forKey: .message) {
            self.code = code
            self.message = message
            self.data = try? c.decodeIfPresent(EIP712Value.self, forKey: .data)
            return
        }
        // Off-spec shape we've seen from Cloudup MCP: bare string in `error`.
        // Surface it as a JSONRPCError so callers see the server's message
        // instead of an opaque DecodingError that hides the real cause.
        let single = try decoder.singleValueContainer()
        if let s = try? single.decode(String.self) {
            self.code = -32000 // generic server error per JSON-RPC 2.0
            self.message = s
            self.data = nil
            return
        }
        throw DecodingError.dataCorruptedError(
            in: single,
            debugDescription: "JSONRPCError must be {code,message} object or a string"
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(code, forKey: .code)
        try c.encode(message, forKey: .message)
        try c.encodeIfPresent(data, forKey: .data)
    }
}

public struct JSONRPCResponse: Codable, Sendable {
    public let id: JSONRPCID?
    public enum Outcome: Sendable { case success(EIP712Value), failure(JSONRPCError) }
    public let outcome: Outcome

    enum CodingKeys: String, CodingKey { case id, result, error }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(JSONRPCID.self, forKey: .id)
        if let err = try c.decodeIfPresent(JSONRPCError.self, forKey: .error) {
            self.outcome = .failure(err)
        } else {
            let value = try c.decodeIfPresent(EIP712Value.self, forKey: .result) ?? .null
            self.outcome = .success(value)
        }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(id, forKey: .id)
        switch outcome {
        case .success(let v): try c.encode(v, forKey: .result)
        case .failure(let e): try c.encode(e, forKey: .error)
        }
    }
}
