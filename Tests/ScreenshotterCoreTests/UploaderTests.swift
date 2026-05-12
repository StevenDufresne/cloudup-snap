import Testing
import Foundation
@testable import ScreenshotterCore

private final class StubWallet: WalletProtocol, @unchecked Sendable {
    let address = EthereumAddress(bytes: Data(repeating: 0xaa, count: 20))
    let txHash: String
    init(txHash: String) { self.txHash = txHash }
    func sendTransfer(
        to: EthereumAddress, amount: UInt64, contract: EthereumAddress,
        rpc: EthereumRPC, receiptPoll: ReceiptPollPolicy
    ) async throws -> String { txHash }
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
