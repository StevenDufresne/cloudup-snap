import Testing
import Foundation
@testable import ScreenshotterCore

private final class StubWallet: WalletProtocol, @unchecked Sendable {
    let address: EthereumAddress
    var lastTransferArgs: (to: EthereumAddress, amount: UInt64, contract: EthereumAddress)?
    let returnedTxHash: String

    init(returnedTxHash: String = "0xfeedbeef000000000000000000000000000000000000000000000000000000aa") {
        self.address = EthereumAddress(bytes: Data(repeating: 0xaa, count: 20))
        self.returnedTxHash = returnedTxHash
    }

    func sendTransfer(
        to: EthereumAddress, amount: UInt64, contract: EthereumAddress,
        rpc: EthereumRPC, receiptPoll: ReceiptPollPolicy
    ) async throws -> String {
        lastTransferArgs = (to, amount, contract)
        return returnedTxHash
    }
    func signX402Payment(_ req: X402PaymentRequirements, now: Date) throws -> X402PaymentPayload {
        X402PaymentPayload(
            x402Version: 1, scheme: req.scheme, network: req.network,
            payload: X402PaymentPayload.Inner(
                signature: "0x" + String(repeating: "00", count: 65),
                authorization: X402Authorization(
                    from: address.hexString(),
                    to: "0x" + req.payTo.hexEncodedString(),
                    value: req.maxAmountRequired,
                    validAfter: "0", validBefore: "9999999999",
                    nonce: "0x" + String(repeating: "42", count: 32))))
    }
}

@Test func paymentClientSettlesChallengeUnderCap() async throws {
    let payload = try JSONDecoder().decode(
        PaymentChallengePayload.self,
        from: PaymentChallengeSamples.basicChallengeJSON.data(using: .utf8)!
    )
    let challenge = payload.challenges[0]
    let wallet = StubWallet()
    let rpc = MockEthereumRPC()
    let client = PaymentClient(wallet: wallet, rpc: rpc, capUSD: Decimal(string: "0.50")!)
    let credential = try await client.settle(challenge: challenge)
    #expect(credential.method == "erc20-usdc-base-sepolia")
    #expect(credential.challengeId == "ch_abc123")
    #expect(credential.settlementTxHash == "0xfeedbeef000000000000000000000000000000000000000000000000000000aa")
    #expect(wallet.lastTransferArgs?.amount == 100000)  // 0.10 USDC × 10^6
}

@Test func paymentClientRejectsOverCap() async throws {
    let payload = try JSONDecoder().decode(
        PaymentChallengePayload.self,
        from: PaymentChallengeSamples.basicChallengeJSON.data(using: .utf8)!
    )
    let challenge = payload.challenges[0]
    let wallet = StubWallet()
    let rpc = MockEthereumRPC()
    let client = PaymentClient(wallet: wallet, rpc: rpc, capUSD: Decimal(string: "0.05")!)
    do {
        _ = try await client.settle(challenge: challenge)
        Issue.record("expected capExceeded")
    } catch PaymentError.capExceeded(let q, let cap) {
        #expect(q == Decimal(string: "0.10"))
        #expect(cap == Decimal(string: "0.05"))
    } catch {
        Issue.record("wrong error: \(error)")
    }
}

@Test func paymentClientRejectsWhenNoMethodSupported() async throws {
    let json = """
    {"challenges":[{"challenge_id":"x","amount":"0.10","methods":[{"id":"unsupported","network":"foo","currency":"FOO","currency_contract":"","currency_decimals":0,"recipient_address":""}]}]}
    """.data(using: .utf8)!
    let payload = try JSONDecoder().decode(PaymentChallengePayload.self, from: json)
    let challenge = payload.challenges[0]
    let wallet = StubWallet()
    let rpc = MockEthereumRPC()
    let client = PaymentClient(wallet: wallet, rpc: rpc, capUSD: 1)
    await #expect(throws: PaymentError.self) {
        _ = try await client.settle(challenge: challenge)
    }
}
