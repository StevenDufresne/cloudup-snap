import Testing
import Foundation
@testable import ScreenshotterCore

@Test func paymentChallengeParses() throws {
    let data = PaymentChallengeSamples.basicChallengeJSON.data(using: .utf8)!
    let payload = try JSONDecoder().decode(PaymentChallengePayload.self, from: data)
    let challenge = payload.challenges[0]
    #expect(challenge.challengeId == "ch_abc123")
    #expect(challenge.amount == Decimal(string: "0.10"))
    #expect(challenge.opaque?.stringValue == "srv-nonce-xyz789")
    #expect(challenge.methods.first?.id == "erc20-usdc-base-sepolia")
    #expect(challenge.methods.first?.currencyDecimals == 6)
}

@Test func paymentChallengePicksFirstSupportedMethod() throws {
    let data = PaymentChallengeSamples.basicChallengeJSON.data(using: .utf8)!
    let payload = try JSONDecoder().decode(PaymentChallengePayload.self, from: data)
    let method = payload.challenges[0].firstSupportedMethod()
    #expect(method?.id == "erc20-usdc-base-sepolia")
    let addr = try method?.recipientEthereumAddress()
    #expect(addr?.bytes.count == 20)
}

@Test func paymentChallengeRejectsMalformedAddressLength() throws {
    let json = """
    {"challenges":[{"challenge_id":"x","amount":"0.10","methods":[{"id":"erc20-test","network":"foo","currency":"FOO","currency_contract":"0xdeadbeef","currency_decimals":6,"recipient_address":"0xc5f06701bd664159620f1a83a64a57ebcef9151b"}]}]}
    """.data(using: .utf8)!
    let payload = try JSONDecoder().decode(PaymentChallengePayload.self, from: json)
    let method = payload.challenges[0].firstSupportedMethod()
    // currency_contract is 4 bytes — must throw, not crash on precondition.
    #expect(throws: PaymentError.self) { try method?.currencyContractAddress() }
}
