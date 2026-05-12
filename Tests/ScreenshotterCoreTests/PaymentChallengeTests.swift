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
    #expect(method?.recipientAddress.hexEncodedString() != nil)
}
