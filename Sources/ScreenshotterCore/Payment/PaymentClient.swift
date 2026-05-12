import Foundation

public struct PaymentClient: Sendable {
    public let wallet: WalletProtocol
    public let rpc: EthereumRPC
    public let capUSD: Decimal
    public let receiptPoll: ReceiptPollPolicy

    public init(
        wallet: WalletProtocol,
        rpc: EthereumRPC,
        capUSD: Decimal = Decimal(string: "0.50")!,
        receiptPoll: ReceiptPollPolicy = ReceiptPollPolicy()
    ) {
        self.wallet = wallet
        self.rpc = rpc
        self.capUSD = capUSD
        self.receiptPoll = receiptPoll
    }

    public func isPaymentRequired(_ error: JSONRPCError) -> Bool {
        error.code == -32042
    }

    public func extractPayload(from error: JSONRPCError) throws -> PaymentChallengePayload {
        guard let data = error.data else {
            throw PaymentError.malformedChallenge("missing data on -32042 error")
        }
        let json = try JSONEncoder().encode(data)
        do {
            return try JSONDecoder().decode(PaymentChallengePayload.self, from: json)
        } catch {
            throw PaymentError.malformedChallenge("\(error)")
        }
    }

    public func settle(challenge: PaymentChallenge) async throws -> PaymentCredential {
        guard challenge.amount <= capUSD else {
            throw PaymentError.capExceeded(quotedUSD: challenge.amount, capUSD: capUSD)
        }
        guard let method = challenge.firstSupportedMethod() else {
            throw PaymentError.noSupportedMethod(offered: challenge.methods.map(\.id))
        }
        let tokenAmount = try unitsFromDecimal(challenge.amount, decimals: method.currencyDecimals)
        let recipient = try method.recipientEthereumAddress()
        let contract = try method.currencyContractAddress()

        let txHash: String
        do {
            txHash = try await wallet.sendTransfer(
                to: recipient,
                amount: tokenAmount,
                contract: contract,
                rpc: rpc,
                receiptPoll: receiptPoll
            )
        } catch WalletError.transactionReverted(let hash) {
            throw PaymentError.settlementReverted(txHash: hash)
        } catch WalletError.receiptTimeout(let hash) {
            throw PaymentError.settlementTimeout(txHash: hash)
        }
        return PaymentCredential(
            method: method.id,
            challengeId: challenge.challengeId,
            opaque: challenge.opaque,
            settlementTxHash: txHash
        )
    }

    private func unitsFromDecimal(_ amount: Decimal, decimals: Int) throws -> UInt64 {
        var multiplier = Decimal(1)
        for _ in 0..<decimals { multiplier *= 10 }
        var scaled = amount * multiplier
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        let str = (rounded as NSDecimalNumber).stringValue
        guard let u = UInt64(str) else {
            throw PaymentError.malformedChallenge("amount \(amount) not representable as UInt64 token units")
        }
        return u
    }
}
