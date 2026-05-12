import Foundation

public struct PaymentChallengePayload: Decodable, Sendable {
    public let challenges: [PaymentChallenge]
}

public struct PaymentChallenge: Decodable, Sendable {
    public let challengeId: String
    public let sku: String?
    public let amount: Decimal
    public let opaque: EIP712Value?
    public let methods: [PaymentMethod]

    enum CodingKeys: String, CodingKey {
        case challengeId = "challenge_id"
        case sku, amount, opaque, methods
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.challengeId = try c.decode(String.self, forKey: .challengeId)
        self.sku = try c.decodeIfPresent(String.self, forKey: .sku)
        let amountString = try c.decode(String.self, forKey: .amount)
        guard let amount = Decimal(string: amountString) else {
            throw DecodingError.dataCorruptedError(forKey: .amount, in: c, debugDescription: "non-numeric amount")
        }
        self.amount = amount
        self.opaque = try c.decodeIfPresent(EIP712Value.self, forKey: .opaque)
        self.methods = try c.decode([PaymentMethod].self, forKey: .methods)
    }

    public func firstSupportedMethod() -> PaymentMethod? {
        methods.first(where: { m in
            m.id.hasPrefix("eip3009-usdc-")
            || m.id.hasPrefix("erc20-")
            || !m.currencyContract.isEmpty
        })
    }
}

public struct PaymentMethod: Decodable, Sendable {
    public let id: String
    public let network: String
    public let currency: String
    public let currencyContractHex: String
    public let currencyDecimals: Int
    public let recipientAddressHex: String

    enum CodingKeys: String, CodingKey {
        case id, network, currency
        case currencyContract = "currency_contract"
        case currencyDecimals = "currency_decimals"
        case recipientAddress = "recipient_address"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.network = try c.decode(String.self, forKey: .network)
        self.currency = try c.decode(String.self, forKey: .currency)
        self.currencyContractHex = try c.decode(String.self, forKey: .currencyContract)
        self.currencyDecimals = try c.decode(Int.self, forKey: .currencyDecimals)
        self.recipientAddressHex = try c.decode(String.self, forKey: .recipientAddress)
    }

    public var currencyContract: Data { (try? Data(hexString: currencyContractHex)) ?? Data() }
    public var recipientAddress: Data { (try? Data(hexString: recipientAddressHex)) ?? Data() }
}
