import Foundation

public protocol WalletProtocol: Sendable {
    var address: EthereumAddress { get }
    func sendTransfer(
        to: EthereumAddress,
        amount: UInt64,
        contract: EthereumAddress,
        rpc: EthereumRPC,
        receiptPoll: ReceiptPollPolicy
    ) async throws -> String
}

public struct ReceiptPollPolicy: Sendable {
    public let interval: TimeInterval
    public let timeout: TimeInterval
    public init(interval: TimeInterval = 1.0, timeout: TimeInterval = 60.0) {
        self.interval = interval
        self.timeout = timeout
    }
}

public enum WalletError: Error {
    case transactionReverted(txHash: String)
    case receiptTimeout(txHash: String)
}

public struct Wallet: WalletProtocol {
    public let address: EthereumAddress
    private let signer: Secp256k1Signer

    public init(address: EthereumAddress, signer: Secp256k1Signer) {
        self.address = address
        self.signer = signer
    }

    public static func loadOrCreate(
        keychain: KeychainStore,
        service: String,
        account: String
    ) throws -> Wallet {
        let privKey: Data
        if let existing = try keychain.read(account: account, service: service) {
            privKey = existing
        } else {
            let fresh = try Secp256k1Signer.generate()
            try keychain.write(fresh.privateKey, account: account, service: service)
            privKey = fresh.privateKey
        }
        let signer = try Secp256k1Signer(privateKey: privKey)
        let address = EthereumAddress(uncompressedPublicKey: signer.publicKeyUncompressed)
        return Wallet(address: address, signer: signer)
    }

    public func sendTransfer(
        to: EthereumAddress,
        amount: UInt64,
        contract: EthereumAddress,
        rpc: EthereumRPC,
        receiptPoll: ReceiptPollPolicy = ReceiptPollPolicy()
    ) async throws -> String {
        let chainId = try await rpc.chainId()
        let nonce = try await rpc.transactionCount(address: address)
        let tip = try await rpc.maxPriorityFeePerGas()
        let basefee = try await rpc.gasPrice()
        let maxFee = basefee + tip
        let calldata = ERC20.encodeTransfer(to: to.bytes, amount: amount)
        let gas = try await rpc.estimateGas(from: address, to: contract, data: calldata)
        let gasWithMargin = (gas * 12) / 10

        let tx = EIP1559Transaction(
            chainId: chainId,
            nonce: nonce,
            maxPriorityFeePerGas: tip,
            maxFeePerGas: maxFee,
            gasLimit: gasWithMargin,
            to: contract.bytes,
            value: 0,
            data: calldata
        )
        let signed = try tx.sign(with: signer)
        let txHash = try await rpc.sendRawTransaction(signed.rawTransaction)
        try await waitForReceipt(txHash: txHash, rpc: rpc, policy: receiptPoll)
        return txHash
    }

    private func waitForReceipt(txHash: String, rpc: EthereumRPC, policy: ReceiptPollPolicy) async throws {
        let deadline = Date().addingTimeInterval(policy.timeout)
        while Date() < deadline {
            if let receipt = try await rpc.transactionReceipt(txHash) {
                if receipt.didSucceed { return }
                throw WalletError.transactionReverted(txHash: txHash)
            }
            try await Task.sleep(nanoseconds: UInt64(policy.interval * 1_000_000_000))
        }
        throw WalletError.receiptTimeout(txHash: txHash)
    }
}
