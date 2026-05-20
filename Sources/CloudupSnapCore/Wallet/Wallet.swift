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
    func signX402Payment(_ req: X402PaymentRequirements, now: Date) throws -> X402PaymentPayload
}

public extension WalletProtocol {
    /// Default helper that uses the current wall-clock time.
    func signX402Payment(_ req: X402PaymentRequirements) throws -> X402PaymentPayload {
        try signX402Payment(req, now: Date())
    }
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

    public func signX402Payment(_ req: X402PaymentRequirements, now: Date = Date()) throws -> X402PaymentPayload {
        guard let chainId = X402Chain.chainId(for: req.network) else {
            throw WalletError.transactionReverted(txHash: "unknown network: \(req.network)")
        }
        var nonceBytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, 32, &nonceBytes)
        let nonce = Data(nonceBytes)
        // Mirror the Cloudup x402 smoke test: backdate validAfter by 10 min to
        // tolerate clock skew at the facilitator. Some facilitators throw on
        // validAfter=0 (PHP fatal in unverified paths → empty-body 500 from
        // the resource server) instead of returning a structured rejection.
        let nowEpoch = UInt64(now.timeIntervalSince1970)
        let validAfter: UInt64 = nowEpoch > 600 ? nowEpoch - 600 : 0
        let validBefore = nowEpoch + UInt64(req.maxTimeoutSeconds)

        guard let raw = UInt64(req.maxAmountRequired) else {
            throw WalletError.transactionReverted(txHash: "non-numeric maxAmountRequired: \(req.maxAmountRequired)")
        }
        let valueBytes = EIP3009.leftPad(EIP3009.uint64ToData(raw), to: 32)

        let digest = EIP3009.digest(
            domainName: req.assetName,
            domainVersion: req.assetVersion,
            chainId: chainId,
            verifyingContract: req.asset,
            from: address.bytes,
            to: req.payTo,
            value: valueBytes,
            validAfter: validAfter,
            validBefore: validBefore,
            nonce: nonce
        )
        let sig = try signer.signRecoverable(digest: digest)

        // x402 expects v as 27 or 28 (Ethereum convention) — secp256k1 returns
        // 0 or 1, so add 27.
        let vByte = UInt8(27 + Int(sig.v))
        let signatureHex = "0x" + (sig.r + sig.s + Data([vByte])).hexEncodedString()

        // Persistent file log for x402 debugging — separate from the main app
        // log so we can paste the full payload safely.
        let dbg = """
        [x402-sign] domain={name:\(req.assetName), version:\(req.assetVersion), chainId:\(chainId), contract:0x\(req.asset.hexEncodedString())}
        [x402-sign] auth={from:\(address.hexString()), to:0x\(req.payTo.hexEncodedString()), value:\(req.maxAmountRequired), validAfter:\(validAfter), validBefore:\(validBefore), nonce:0x\(nonce.hexEncodedString())}
        [x402-sign] digest=0x\(digest.hexEncodedString())
        [x402-sign] signature=\(signatureHex) (v=\(vByte))

        """
        let logPath = NSHomeDirectory() + "/Library/Logs/CloudupSnap/app.log"
        if let fh = FileHandle(forWritingAtPath: logPath) {
            fh.seekToEndOfFile()
            if let d = dbg.data(using: .utf8) { fh.write(d) }
            try? fh.close()
        }

        return X402PaymentPayload(
            x402Version: 1,
            scheme: req.scheme,
            network: req.network,
            payload: X402PaymentPayload.Inner(
                signature: signatureHex,
                authorization: X402Authorization(
                    from: address.hexString(),
                    to: "0x" + req.payTo.hexEncodedString(),
                    value: req.maxAmountRequired,
                    validAfter: String(validAfter),
                    validBefore: String(validBefore),
                    nonce: "0x" + nonce.hexEncodedString()
                )
            )
        )
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
