import Foundation

public extension Wallet {
    /// Balance in ETH (1 ETH = 1e18 wei). Result is a `Decimal` for UI display.
    func balanceETH(rpc: EthereumRPC) async throws -> Decimal {
        let q: HexQuantity = try await rpc.call("eth_getBalance", params: [address.hexString(), "latest"])
        return weiToDecimal(q.uint64, decimals: 18)
    }

    /// Balance in tokens of `contract`. Uses ERC-20 `balanceOf(address)`.
    func balanceUSDC(contract: EthereumAddress, decimals: Int, rpc: EthereumRPC) async throws -> Decimal {
        // Selector for balanceOf(address): 0x70a08231
        var data = Data([0x70, 0xa0, 0x82, 0x31])
        data.append(Data(count: 12))   // left-pad address to 32 bytes
        data.append(address.bytes)
        let resultHex: String = try await rpc.call("eth_call", params: [[
            "to": contract.hexString(),
            "data": data.hexEncodedString(prefix: true),
        ], "latest"])
        var raw = resultHex
        if raw.hasPrefix("0x") { raw = String(raw.dropFirst(2)) }
        // ERC-20 balanceOf returns uint256. Token balances within human-actionable range
        // fit easily into UInt64; take the rightmost 16 hex chars.
        let suffix = String(raw.suffix(16))
        let units = UInt64(suffix, radix: 16) ?? 0
        return weiToDecimal(units, decimals: decimals)
    }

    private func weiToDecimal(_ wei: UInt64, decimals: Int) -> Decimal {
        var divisor = Decimal(1)
        for _ in 0..<decimals { divisor *= 10 }
        return Decimal(wei) / divisor
    }
}
