import Foundation

public struct EIP1559Transaction {
    public let chainId: UInt64
    public let nonce: UInt64
    public let maxPriorityFeePerGas: UInt64
    public let maxFeePerGas: UInt64
    public let gasLimit: UInt64
    public let to: Data
    public let value: UInt64
    public let data: Data

    public init(
        chainId: UInt64,
        nonce: UInt64,
        maxPriorityFeePerGas: UInt64,
        maxFeePerGas: UInt64,
        gasLimit: UInt64,
        to: Data,
        value: UInt64 = 0,
        data: Data = Data()
    ) {
        precondition(to.count == 20)
        self.chainId = chainId
        self.nonce = nonce
        self.maxPriorityFeePerGas = maxPriorityFeePerGas
        self.maxFeePerGas = maxFeePerGas
        self.gasLimit = gasLimit
        self.to = to
        self.value = value
        self.data = data
    }

    public var signingPayload: Data {
        let fields: [RLPItem] = [
            .uint(chainId),
            .uint(nonce),
            .uint(maxPriorityFeePerGas),
            .uint(maxFeePerGas),
            .uint(gasLimit),
            .bytes(to),
            .uint(value),
            .bytes(data),
            .list([]),
        ]
        return Data([0x02]) + RLP.encode(.list(fields))
    }

    public func sign(with signer: Secp256k1Signer) throws -> SignedEIP1559Transaction {
        let hash = signingPayload.keccak256()
        let sig = try signer.signRecoverable(digest: hash)
        let signedFields: [RLPItem] = [
            .uint(chainId),
            .uint(nonce),
            .uint(maxPriorityFeePerGas),
            .uint(maxFeePerGas),
            .uint(gasLimit),
            .bytes(to),
            .uint(value),
            .bytes(data),
            .list([]),
            .uint(UInt64(sig.v)),
            .bigUint(sig.r),
            .bigUint(sig.s),
        ]
        let raw = Data([0x02]) + RLP.encode(.list(signedFields))
        return SignedEIP1559Transaction(rawTransaction: raw, transactionHash: raw.keccak256())
    }
}

public struct SignedEIP1559Transaction {
    public let rawTransaction: Data
    public let transactionHash: Data
}
