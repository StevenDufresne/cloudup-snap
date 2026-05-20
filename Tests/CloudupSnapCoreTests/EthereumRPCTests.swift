import Testing
import Foundation
@testable import CloudupSnapCore

@Test func ethereumRPCParsesChainId() async throws {
    let rpc = MockEthereumRPC()
    rpc.canned["eth_chainId"] = "0x14a34"  // 84532 = Base Sepolia
    let id: HexQuantity = try await rpc.call("eth_chainId", params: [])
    #expect(id.uint64 == 84532)
}

@Test func ethereumRPCEncodesAddressParam() async throws {
    let rpc = MockEthereumRPC()
    rpc.canned["eth_getTransactionCount"] = "0x0"
    let _: HexQuantity = try await rpc.call(
        "eth_getTransactionCount",
        params: ["0x3E64B7838e791d5E2b766C7AFae5C3f2D57F9Cc7", "latest"]
    )
    #expect(rpc.receivedCalls.first?.method == "eth_getTransactionCount")
}

@Test func hexQuantityRoundTrips() throws {
    let decoded = try HexQuantity(hex: "0x14a34")
    #expect(decoded.uint64 == 84532)
    #expect(decoded.hexString == "0x14a34")
}
