import Foundation

public enum HexError: Error, Equatable {
    case oddLength
    case invalidCharacter(Character)
}

public extension Data {
    func hexEncodedString(prefix: Bool = false) -> String {
        let body = map { String(format: "%02x", $0) }.joined()
        return prefix ? "0x" + body : body
    }

    init(hexString: String) throws {
        var s = hexString
        if s.hasPrefix("0x") || s.hasPrefix("0X") {
            s = String(s.dropFirst(2))
        }
        guard s.count % 2 == 0 else { throw HexError.oddLength }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(s.count / 2)
        var index = s.startIndex
        while index < s.endIndex {
            let next = s.index(index, offsetBy: 2)
            guard let byte = UInt8(s[index..<next], radix: 16) else {
                throw HexError.invalidCharacter(s[index])
            }
            bytes.append(byte)
            index = next
        }
        self = Data(bytes)
    }
}
