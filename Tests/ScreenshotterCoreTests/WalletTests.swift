import Testing
import Foundation
@testable import ScreenshotterCore

@Test func walletGeneratesAndPersists() throws {
    let store = InMemoryKeychainStore()
    let a = try Wallet.loadOrCreate(keychain: store, service: "test", account: "default")
    let b = try Wallet.loadOrCreate(keychain: store, service: "test", account: "default")
    #expect(a.address == b.address)
    #expect(a.address.bytes.count == 20)
}

@Test func walletSendTransferOrchestratesRPCCalls() async throws {
    let store = InMemoryKeychainStore()
    let wallet = try Wallet.loadOrCreate(keychain: store, service: "test", account: "default")
    let rpc = MockEthereumRPC()
    rpc.canned["eth_chainId"] = "0x14a34"
    rpc.canned["eth_getTransactionCount"] = "0x5"
    rpc.canned["eth_maxPriorityFeePerGas"] = "0x3b9aca00"
    rpc.canned["eth_gasPrice"] = "0x77359400"
    rpc.canned["eth_estimateGas"] = "0xea60"
    rpc.canned["eth_sendRawTransaction"] = "0xabc1230000000000000000000000000000000000000000000000000000000001"
    rpc.canned["eth_getTransactionReceipt"] = [
        "transactionHash": "0xabc1230000000000000000000000000000000000000000000000000000000001",
        "blockNumber": "0x123",
        "status": "0x1",
    ]
    let to = try Data(hexString: "0xc5F06701bd664159620F1a83A64A57ebCEF9151b")
    let contract = try Data(hexString: "0x036CbD53842c5426634e7929541eC2318f3dCF7e")

    let txHash = try await wallet.sendTransfer(
        to: EthereumAddress(bytes: to),
        amount: 50000,
        contract: EthereumAddress(bytes: contract),
        rpc: rpc,
        receiptPoll: ReceiptPollPolicy(interval: 0.01, timeout: 1.0)
    )
    #expect(txHash == "0xabc1230000000000000000000000000000000000000000000000000000000001")
    #expect(rpc.receivedCalls.map { $0.method }.contains("eth_sendRawTransaction"))
}
