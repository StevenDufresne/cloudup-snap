import Foundation

/// Parsed representation of a single entry from an x402 v1 challenge's
/// `accepts` array. The challenge itself comes from Cloudup's success response
/// (NOT a JSON-RPC error); we detect it in `Uploader.extractShareURL`.
public struct X402PaymentRequirements: Equatable, Sendable {
    public let scheme: String           // e.g. "exact"
    public let network: String          // e.g. "base-sepolia"
    public let maxAmountRequired: String  // raw token units as decimal string
    public let asset: Data              // ERC-20 contract address, 20 bytes
    public let payTo: Data              // recipient address, 20 bytes
    public let resource: String         // e.g. "mcp://tool/quick_upload"
    public let description: String?
    public let maxTimeoutSeconds: Int
    public let assetName: String        // EIP-712 domain.name (from `extra`)
    public let assetVersion: String     // EIP-712 domain.version (from `extra`)
    public let assetDecimals: Int       // assumed 6 for USDC (not in challenge)

    public init(
        scheme: String, network: String, maxAmountRequired: String,
        asset: Data, payTo: Data, resource: String, description: String?,
        maxTimeoutSeconds: Int, assetName: String, assetVersion: String,
        assetDecimals: Int = 6
    ) {
        self.scheme = scheme
        self.network = network
        self.maxAmountRequired = maxAmountRequired
        self.asset = asset
        self.payTo = payTo
        self.resource = resource
        self.description = description
        self.maxTimeoutSeconds = maxTimeoutSeconds
        self.assetName = assetName
        self.assetVersion = assetVersion
        self.assetDecimals = assetDecimals
    }

    /// Human-readable amount in the token's decimal units (e.g. 0.05 for 50000
    /// raw USDC units at 6 decimals).
    public var amountDecimal: Decimal {
        guard let raw = Decimal(string: maxAmountRequired) else { return 0 }
        var divisor = Decimal(1)
        for _ in 0..<assetDecimals { divisor *= 10 }
        return raw / divisor
    }
}

/// EIP-155 chain id for each x402 `network` string we support.
public enum X402Chain {
    public static func chainId(for network: String) -> UInt64? {
        switch network {
        case "base-sepolia":      return 84532
        case "base":              return 8453
        case "ethereum",
             "mainnet":           return 1
        case "sepolia":           return 11155111
        case "polygon":           return 137
        case "optimism":          return 10
        case "optimism-sepolia":  return 11155420
        case "arbitrum":          return 42161
        default:                  return nil
        }
    }
}

/// Inner authorization object — the EIP-3009 `TransferWithAuthorization`
/// fields, all encoded as 0x-hex or decimal strings per the spec.
public struct X402Authorization: Codable, Equatable, Sendable {
    public let from: String         // 0x… 20 bytes
    public let to: String           // 0x…
    public let value: String        // decimal string (raw token units)
    public let validAfter: String   // decimal string
    public let validBefore: String  // decimal string
    public let nonce: String        // 0x… 32 bytes
}

/// The full payload we base64-encode and send as `X-PAYMENT`.
public struct X402PaymentPayload: Codable, Equatable, Sendable {
    public let x402Version: Int
    public let scheme: String
    public let network: String
    public let payload: Inner

    public struct Inner: Codable, Equatable, Sendable {
        public let signature: String  // 0x… 65 bytes (r||s||v)
        public let authorization: X402Authorization
    }

    /// JSON-then-base64-encode for the x402 HTTP transport's `X-PAYMENT`
    /// header. Cloudup uses the MCP transport (`_meta["x402/payment"]`) — see
    /// `asEIP712Value` — so this is currently unused, but kept for parity with
    /// the spec in case a non-MCP server ever appears.
    public func headerValue() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = []
        let json = try encoder.encode(self)
        return json.base64EncodedString()
    }

    /// Structured representation for the MCP transport. Per
    /// coinbase/x402 specs/transports-v1/mcp.md, payment goes inside the
    /// JSON-RPC body as `params._meta["x402/payment"] = <this object>`.
    public var asEIP712Value: EIP712Value {
        .object([
            "x402Version": .number(String(x402Version)),
            "scheme": .string(scheme),
            "network": .string(network),
            "payload": .object([
                "signature": .string(payload.signature),
                "authorization": .object([
                    "from": .string(payload.authorization.from),
                    "to": .string(payload.authorization.to),
                    "value": .string(payload.authorization.value),
                    "validAfter": .string(payload.authorization.validAfter),
                    "validBefore": .string(payload.authorization.validBefore),
                    "nonce": .string(payload.authorization.nonce),
                ]),
            ]),
        ])
    }
}

/// Parse an x402 v1 challenge from the text the server returned inside an MCP
/// tool result. Returns nil if `text` is not a recognizable x402 challenge.
public func parseX402Challenge(from text: String) -> X402PaymentRequirements? {
    guard let data = text.data(using: .utf8),
          let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          raw["x402Version"] != nil,
          let accepts = raw["accepts"] as? [[String: Any]],
          let first = accepts.first,
          let scheme = first["scheme"] as? String,
          let network = first["network"] as? String,
          let maxAmount = first["maxAmountRequired"] as? String,
          let assetHex = first["asset"] as? String,
          let payToHex = first["payTo"] as? String,
          let resource = first["resource"] as? String,
          let asset = try? Data(hexString: assetHex), asset.count == 20,
          let payTo = try? Data(hexString: payToHex), payTo.count == 20
    else { return nil }

    let extra = first["extra"] as? [String: Any]
    let assetName = (extra?["name"] as? String) ?? "USDC"
    let assetVersion = (extra?["version"] as? String) ?? "2"
    let description = first["description"] as? String
    let timeout = (first["maxTimeoutSeconds"] as? Int) ?? 60

    return X402PaymentRequirements(
        scheme: scheme,
        network: network,
        maxAmountRequired: maxAmount,
        asset: asset,
        payTo: payTo,
        resource: resource,
        description: description,
        maxTimeoutSeconds: timeout,
        assetName: assetName,
        assetVersion: assetVersion
    )
}
