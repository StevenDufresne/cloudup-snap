import Foundation

public struct PaymentCredential: Codable, Equatable, Sendable {
    public let method: String
    public let challengeId: String
    public let opaque: EIP712Value?
    public let settlementTxHash: String

    enum CodingKeys: String, CodingKey {
        case method
        case challengeId = "challenge_id"
        case opaque
        case settlementTxHash = "settlement_tx_hash"
    }

    public var asEIP712Value: EIP712Value {
        var obj: [String: EIP712Value] = [
            "method": .string(method),
            "challenge_id": .string(challengeId),
            "settlement_tx_hash": .string(settlementTxHash),
        ]
        if let o = opaque { obj["opaque"] = o }
        return .object(obj)
    }
}
