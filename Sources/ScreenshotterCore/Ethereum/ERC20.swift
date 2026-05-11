import Foundation

public enum ERC20Error: Error {
    case addressMustBe20Bytes
}

public enum ERC20 {
    public static let transferSelector: Data = "transfer(address,uint256)"
        .data(using: .utf8)!
        .keccak256()
        .prefix(4)

    /// `transfer(address,uint256)` calldata. Address must be 20 bytes.
    public static func encodeTransfer(to address: Data, amount: UInt64) -> Data {
        precondition(address.count == 20)
        var out = Data(transferSelector)
        out.append(leftPad(address, to: 32))
        out.append(leftPad(bigEndianBytes(amount), to: 32))
        return out
    }

    public static func encodeTransferOrThrow(to address: Data, amount: UInt64) throws -> Data {
        guard address.count == 20 else { throw ERC20Error.addressMustBe20Bytes }
        return encodeTransfer(to: address, amount: amount)
    }

    public static func encodeTransfer(to address: Data, amountBigEndian: Data) -> Data {
        precondition(address.count == 20)
        precondition(amountBigEndian.count <= 32)
        var out = Data(transferSelector)
        out.append(leftPad(address, to: 32))
        out.append(leftPad(amountBigEndian, to: 32))
        return out
    }

    private static func leftPad(_ data: Data, to width: Int) -> Data {
        if data.count >= width { return data.suffix(width) }
        return Data(count: width - data.count) + data
    }

    private static func bigEndianBytes(_ u: UInt64) -> Data {
        var result = Data(count: 8)
        for i in 0..<8 { result[7 - i] = UInt8(truncatingIfNeeded: u >> (i * 8)) }
        var start = result.startIndex
        while start < result.endIndex, result[start] == 0 { start = result.index(after: start) }
        return result.subdata(in: start..<result.endIndex)
    }
}
