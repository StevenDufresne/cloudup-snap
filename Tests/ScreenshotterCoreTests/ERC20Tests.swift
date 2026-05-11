import Testing
import Foundation
@testable import ScreenshotterCore

@Test func erc20TransferCalldataMatchesKnownVector() throws {
    let recipient = try Data(hexString: "0xc5F06701bd664159620F1a83A64A57ebCEF9151b")
    let amount: UInt64 = 50000
    let calldata = ERC20.encodeTransfer(to: recipient, amount: amount)
    let hex = calldata.hexEncodedString(prefix: true)
    #expect(hex == "0xa9059cbb000000000000000000000000c5f06701bd664159620f1a83a64a57ebcef9151b000000000000000000000000000000000000000000000000000000000000c350")
    #expect(calldata.count == 68)
}

@Test func erc20TransferSelectorIsKnown() {
    #expect(ERC20.transferSelector.hexEncodedString() == "a9059cbb")
}

@Test func erc20TransferRejectsBadAddressLength() {
    #expect(throws: ERC20Error.self) {
        _ = try ERC20.encodeTransferOrThrow(to: Data([0x01, 0x02, 0x03]), amount: 1)
    }
}
