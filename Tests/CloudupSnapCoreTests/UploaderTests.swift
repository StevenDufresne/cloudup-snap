import Testing
import Foundation
@testable import CloudupSnapCore

private final class StubWallet: WalletProtocol, @unchecked Sendable {
    let address = EthereumAddress(bytes: Data(repeating: 0xaa, count: 20))
    let txHash: String
    init(txHash: String) { self.txHash = txHash }
    func sendTransfer(
        to: EthereumAddress, amount: UInt64, contract: EthereumAddress,
        rpc: EthereumRPC, receiptPoll: ReceiptPollPolicy
    ) async throws -> String { txHash }
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

@Test func uploaderPaysAndReturnsShareURL() async throws {
    let wallet = StubWallet(txHash: "0xabc1230000000000000000000000000000000000000000000000000000000001")
    let rpc = MockEthereumRPC()
    let payment = PaymentClient(wallet: wallet, rpc: rpc)
    let transport = MockMCPTransport()

    let challengeJSON = PaymentChallengeSamples.basicChallengeJSON
    let challenge1 = """
    {"jsonrpc":"2.0","id":1,"error":{"code":-32042,"message":"payment required","data":\(challengeJSON)}}
    """
    let success2 = #"{"jsonrpc":"2.0","id":2,"result":{"item_id":"abc","share_url":"https://stage-cloudup.com/s/abc/abc"}}"#
    transport.queuedResponses = [
        try JSONDecoder().decode(JSONRPCResponse.self, from: challenge1.data(using: .utf8)!),
        try JSONDecoder().decode(JSONRPCResponse.self, from: success2.data(using: .utf8)!),
    ]

    let mcp = MCPClient(transport: transport)
    let uploader = Uploader(mcp: mcp, payment: payment)
    let url = try await uploader.upload(
        data: Data([0x89, 0x50, 0x4e, 0x47]),
        filename: "x.png",
        mime: "image/png"
    )
    #expect(url.absoluteString == "https://stage-cloudup.com/s/abc/abc")
    #expect(transport.receivedRequests.count == 2)

    let retryParams = transport.receivedRequests[1].request.params
    let credential = retryParams?["_meta"]?.objectValue?["org.paymentauth/credential"]?.objectValue
    #expect(credential?["method"] == .string("erc20-usdc-base-sepolia"))
    #expect(credential?["settlement_tx_hash"] == .string("0xabc1230000000000000000000000000000000000000000000000000000000001"))
}

@Test func uploaderAttachesX402PaymentToMetaOnRetry() async throws {
    // x402 MCP transport: a successful tools/call result with isError:true and
    // an inline x402 challenge in content[0].text. On retry the signed payload
    // MUST appear at params._meta["x402/payment"] — NOT in an X-PAYMENT header.
    let wallet = StubWallet(txHash: "0xunused")
    let rpc = MockEthereumRPC()
    let payment = PaymentClient(wallet: wallet, rpc: rpc)
    let transport = MockMCPTransport()

    let challengeText = #"{\"x402Version\":1,\"error\":\"Payment required\",\"accepts\":[{\"scheme\":\"exact\",\"network\":\"base-sepolia\",\"maxAmountRequired\":\"50000\",\"asset\":\"0x036CbD53842c5426634e7929541eC2318f3dCF7e\",\"payTo\":\"0xc5F06701bD664159620f1a83A64a57EBCef9151b\",\"resource\":\"mcp://tool/quick_upload\",\"description\":\"hotlink-90d\",\"maxTimeoutSeconds\":60,\"extra\":{\"name\":\"USDC\",\"version\":\"2\"}}]}"#
    let challenge1 = """
    {"jsonrpc":"2.0","id":1,"result":{"isError":true,"content":[{"type":"text","text":"\(challengeText)"}]}}
    """
    let success2 = #"{"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"{\"share_url\":\"https://stage-cloudup.com/s/x/y\"}"}]}}"#
    transport.queuedResponses = [
        try JSONDecoder().decode(JSONRPCResponse.self, from: challenge1.data(using: .utf8)!),
        try JSONDecoder().decode(JSONRPCResponse.self, from: success2.data(using: .utf8)!),
    ]

    let mcp = MCPClient(transport: transport)
    let uploader = Uploader(mcp: mcp, payment: payment)
    let url = try await uploader.upload(data: Data([0x89]), filename: "x.png", mime: "image/png")
    #expect(url.absoluteString == "https://stage-cloudup.com/s/x/y")
    #expect(transport.receivedRequests.count == 2)

    let retry = transport.receivedRequests[1]
    // Sanity: nothing landed in HTTP headers — must be in JSON-RPC body.
    #expect(retry.headers["X-PAYMENT"] == nil)
    #expect(retry.headers["x-payment"] == nil)

    let xpayment = retry.request.params?["_meta"]?.objectValue?["x402/payment"]?.objectValue
    #expect(xpayment != nil)
    #expect(xpayment?["x402Version"] == .number("1"))
    #expect(xpayment?["scheme"] == .string("exact"))
    #expect(xpayment?["network"] == .string("base-sepolia"))
    let inner = xpayment?["payload"]?.objectValue
    #expect(inner?["signature"]?.stringValue?.hasPrefix("0x") == true)
    let auth = inner?["authorization"]?.objectValue
    #expect(auth?["value"] == .string("50000"))
    #expect(auth?["from"]?.stringValue?.hasPrefix("0x") == true)
    #expect(auth?["nonce"]?.stringValue?.hasPrefix("0x") == true)
}

@Test func uploaderSurfacesCapExceeded() async throws {
    let wallet = StubWallet(txHash: "0x")
    let rpc = MockEthereumRPC()
    let payment = PaymentClient(wallet: wallet, rpc: rpc, capUSD: Decimal(string: "0.01")!)
    let transport = MockMCPTransport()

    let challengeJSON = PaymentChallengeSamples.basicChallengeJSON
    let challenge1 = """
    {"jsonrpc":"2.0","id":1,"error":{"code":-32042,"message":"payment required","data":\(challengeJSON)}}
    """
    transport.queuedResponses = [
        try JSONDecoder().decode(JSONRPCResponse.self, from: challenge1.data(using: .utf8)!),
    ]
    let mcp = MCPClient(transport: transport)
    let uploader = Uploader(mcp: mcp, payment: payment)
    await #expect(throws: PaymentError.self) {
        _ = try await uploader.upload(data: Data(), filename: "x.png", mime: "image/png")
    }
}
