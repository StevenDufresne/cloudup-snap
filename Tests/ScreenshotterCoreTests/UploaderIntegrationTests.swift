import Testing
import Foundation
@testable import ScreenshotterCore

@Test(.disabled(
    if: ProcessInfo.processInfo.environment["SCREENSHOTTER_INTEGRATION"] != "1"
       || ProcessInfo.processInfo.environment["SCREENSHOTTER_TEST_WALLET_KEY"] == nil,
    "Set SCREENSHOTTER_INTEGRATION=1 and SCREENSHOTTER_TEST_WALLET_KEY=0x... to run"
))
func integrationPaidUploadAgainstCloudupStage() async throws {
    let keyHex = ProcessInfo.processInfo.environment["SCREENSHOTTER_TEST_WALLET_KEY"]!
    let mcpEndpoint = URL(string: ProcessInfo.processInfo.environment["MCP_ENDPOINT"]
        ?? "https://api.stage-cloudup.com/mcp/public")!
    let rpcEndpoint = URL(string: ProcessInfo.processInfo.environment["BASE_SEPOLIA_RPC"]
        ?? "https://sepolia.base.org")!

    let priv = try Data(hexString: keyHex)
    let signer = try Secp256k1Signer(privateKey: priv)
    let address = EthereumAddress(uncompressedPublicKey: signer.publicKeyUncompressed)
    let wallet = Wallet(address: address, signer: signer)

    let rpc = HTTPEthereumRPC(endpoint: rpcEndpoint)
    let payment = PaymentClient(
        wallet: wallet,
        rpc: rpc,
        capUSD: Decimal(string: "0.50")!,
        receiptPoll: ReceiptPollPolicy(interval: 2.0, timeout: 120.0)
    )
    let transport = StreamableHTTPTransport(endpoint: mcpEndpoint)
    let mcp = MCPClient(transport: transport)
    let uploader = Uploader(mcp: mcp, payment: payment)

    // Minimal valid PNG (1x1 transparent)
    let pngHex = "89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000d4944415478da636400000000050001a5f645080000000049454e44ae426082"
    let png = try Data(hexString: pngHex)

    let url = try await uploader.upload(data: png, filename: "integration.png", mime: "image/png")
    #expect(url.absoluteString.contains("stage-cloudup.com"))
}
