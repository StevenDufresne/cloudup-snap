import Foundation

public enum RLPItem: Sendable {
    case bytes(Data)
    case uint(UInt64)
    case bigUint(Data)        // big-endian, for uint256 values exceeding UInt64
    case list([RLPItem])
}

public enum RLP {
    public static func encode(_ item: RLPItem) -> Data {
        switch item {
        case .bytes(let b):
            return encodeBytes(b)
        case .uint(let u):
            return encodeBytes(stripLeadingZeros(bigEndianBytes(u)))
        case .bigUint(let b):
            return encodeBytes(stripLeadingZeros(b))
        case .list(let items):
            var payload = Data()
            for sub in items { payload.append(encode(sub)) }
            return encodeListPrefix(payload.count) + payload
        }
    }

    private static func encodeBytes(_ data: Data) -> Data {
        if data.count == 1, data[data.startIndex] < 0x80 {
            return data
        }
        if data.count <= 55 {
            return Data([UInt8(0x80 + data.count)]) + data
        }
        let lengthBytes = bigEndianBytes(UInt64(data.count))
        let stripped = stripLeadingZeros(lengthBytes)
        return Data([UInt8(0xb7 + stripped.count)]) + stripped + data
    }

    private static func encodeListPrefix(_ payloadLength: Int) -> Data {
        if payloadLength <= 55 {
            return Data([UInt8(0xc0 + payloadLength)])
        }
        let lengthBytes = bigEndianBytes(UInt64(payloadLength))
        let stripped = stripLeadingZeros(lengthBytes)
        return Data([UInt8(0xf7 + stripped.count)]) + stripped
    }

    private static func bigEndianBytes(_ u: UInt64) -> Data {
        var result = Data(count: 8)
        for i in 0..<8 {
            result[7 - i] = UInt8(truncatingIfNeeded: u >> (i * 8))
        }
        return result
    }

    private static func stripLeadingZeros(_ data: Data) -> Data {
        var i = data.startIndex
        while i < data.endIndex, data[i] == 0 { i = data.index(after: i) }
        return data.subdata(in: i..<data.endIndex)
    }
}
