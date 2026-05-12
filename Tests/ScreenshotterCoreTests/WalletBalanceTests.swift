import Testing
import Foundation
@testable import ScreenshotterCore

@Test func walletBalanceETH() async throws {
    let store = InMemoryKeychainStore()
    let wallet = try Wallet.loadOrCreate(keychain: store, service: "t", account: "a")
    let rpc = MockEthereumRPC()
    rpc.canned["eth_getBalance"] = "0xde0b6b3a7640000"  // 1 ETH in wei (1e18)
    let balance = try await wallet.balanceETH(rpc: rpc)
    #expect(balance == Decimal(string: "1.0"))
}

@Test func walletBalanceUSDC() async throws {
    let store = InMemoryKeychainStore()
    let wallet = try Wallet.loadOrCreate(keychain: store, service: "t", account: "a")
    let rpc = MockEthereumRPC()
    // 1,234,567 raw units = 1.234567 USDC at 6 decimals
    rpc.canned["eth_call"] = "0x000000000000000000000000000000000000000000000000000000000012d687"
    let contract = EthereumAddress(bytes: Data(repeating: 0x01, count: 20))
    let balance = try await wallet.balanceUSDC(contract: contract, decimals: 6, rpc: rpc)
    #expect(balance == Decimal(string: "1.234567"))
}
