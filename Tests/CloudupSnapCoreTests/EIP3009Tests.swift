import Testing
import Foundation
@testable import CloudupSnapCore

@Test func eip3009DigestIsDeterministic() throws {
    // The hash is keccak256(0x1901 || domainSeparator || structHash). Two calls
    // with identical inputs MUST produce the same digest — sanity check.
    let from = Data(repeating: 0xaa, count: 20)
    let to   = Data(repeating: 0xbb, count: 20)
    let asset = Data(repeating: 0xcc, count: 20)
    let value = EIP3009.leftPad(EIP3009.uint64ToData(50000), to: 32)
    let nonce = Data(repeating: 0x42, count: 32)

    let d1 = EIP3009.digest(
        domainName: "USDC", domainVersion: "2",
        chainId: 84532,
        verifyingContract: asset,
        from: from, to: to, value: value,
        validAfter: 0, validBefore: 9999999999,
        nonce: nonce
    )
    let d2 = EIP3009.digest(
        domainName: "USDC", domainVersion: "2",
        chainId: 84532,
        verifyingContract: asset,
        from: from, to: to, value: value,
        validAfter: 0, validBefore: 9999999999,
        nonce: nonce
    )
    #expect(d1.count == 32)
    #expect(d1 == d2)
}

@Test func eip3009DigestChangesWithEveryInput() throws {
    // Mutating any input field must change the resulting digest.
    let baseline = EIP3009.digest(
        domainName: "USDC", domainVersion: "2",
        chainId: 84532,
        verifyingContract: Data(repeating: 0xcc, count: 20),
        from: Data(repeating: 0xaa, count: 20),
        to: Data(repeating: 0xbb, count: 20),
        value: EIP3009.leftPad(EIP3009.uint64ToData(50000), to: 32),
        validAfter: 0, validBefore: 9999999999,
        nonce: Data(repeating: 0x42, count: 32)
    )

    // chainId differs
    let diff1 = EIP3009.digest(
        domainName: "USDC", domainVersion: "2", chainId: 1,
        verifyingContract: Data(repeating: 0xcc, count: 20),
        from: Data(repeating: 0xaa, count: 20),
        to: Data(repeating: 0xbb, count: 20),
        value: EIP3009.leftPad(EIP3009.uint64ToData(50000), to: 32),
        validAfter: 0, validBefore: 9999999999,
        nonce: Data(repeating: 0x42, count: 32))
    #expect(diff1 != baseline)

    // nonce differs
    let diff2 = EIP3009.digest(
        domainName: "USDC", domainVersion: "2", chainId: 84532,
        verifyingContract: Data(repeating: 0xcc, count: 20),
        from: Data(repeating: 0xaa, count: 20),
        to: Data(repeating: 0xbb, count: 20),
        value: EIP3009.leftPad(EIP3009.uint64ToData(50000), to: 32),
        validAfter: 0, validBefore: 9999999999,
        nonce: Data(repeating: 0x43, count: 32))
    #expect(diff2 != baseline)
}

@Test func x402PayloadRoundTripsThroughBase64() throws {
    let payload = X402PaymentPayload(
        x402Version: 1,
        scheme: "exact",
        network: "base-sepolia",
        payload: X402PaymentPayload.Inner(
            signature: "0x" + String(repeating: "00", count: 65),
            authorization: X402Authorization(
                from: "0x" + String(repeating: "aa", count: 20),
                to:   "0x" + String(repeating: "bb", count: 20),
                value: "50000",
                validAfter: "0",
                validBefore: "9999999999",
                nonce: "0x" + String(repeating: "42", count: 32)
            )
        )
    )
    let header = try payload.headerValue()
    let decodedData = Data(base64Encoded: header)
    #expect(decodedData != nil)
    let decoded = try JSONDecoder().decode(X402PaymentPayload.self, from: decodedData!)
    #expect(decoded == payload)
}

@Test func parseX402ChallengeReadsFields() {
    let text = """
    {"x402Version":1,"error":"Payment required to access this tool","accepts":[
      {"scheme":"exact","network":"base-sepolia","maxAmountRequired":"50000",
       "asset":"0x036CbD53842c5426634e7929541eC2318f3dCF7e",
       "payTo":"0xc5F06701bD664159620f1a83A64a57EBCef9151b",
       "resource":"mcp://tool/quick_upload","description":"hotlink-90d",
       "maxTimeoutSeconds":60,"mimeType":"application/json",
       "extra":{"name":"USDC","version":"2"}}]}
    """
    let req = parseX402Challenge(from: text)
    #expect(req != nil)
    #expect(req?.scheme == "exact")
    #expect(req?.network == "base-sepolia")
    #expect(req?.maxAmountRequired == "50000")
    #expect(req?.assetName == "USDC")
    #expect(req?.assetVersion == "2")
    #expect(req?.maxTimeoutSeconds == 60)
    #expect(req?.amountDecimal == Decimal(string: "0.05"))
}

@Test func parseX402ChallengeRejectsNonChallenge() {
    let text = "{\"item_id\":\"abc\",\"share_url\":\"https://x.test\"}"
    #expect(parseX402Challenge(from: text) == nil)
}
