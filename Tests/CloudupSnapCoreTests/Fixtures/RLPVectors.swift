import Foundation
@testable import CloudupSnapCore

enum RLPVectors {
    static let primitives: [(String, RLPItem, String)] = [
        ("empty string", .bytes(Data()), "80"),
        ("single byte 0", .bytes(Data([0x00])), "00"),
        ("single byte 1", .bytes(Data([0x01])), "01"),
        ("single byte 0x7f", .bytes(Data([0x7f])), "7f"),
        ("two bytes 0x80,0x01", .bytes(Data([0x80, 0x01])), "82" + "8001"),
        ("string 'dog'", .bytes("dog".data(using: .utf8)!), "83" + "646f67"),
        ("uint 0", .uint(0), "80"),
        ("uint 1", .uint(1), "01"),
        ("uint 1024", .uint(1024), "82" + "0400"),
        ("empty list", .list([]), "c0"),
        ("list ['cat','dog']", .list([
            .bytes("cat".data(using: .utf8)!),
            .bytes("dog".data(using: .utf8)!),
        ]), "c8" + "83636174" + "83646f67"),
    ]

    /// "Lorem ipsum dolor sit amet, consectetur adipisicing elit" — 55 bytes
    static let stringLength55: (item: RLPItem, hex: String) = {
        let s = "Lorem ipsum dolor sit amet, consectetur adipisicing eli"
        let bytes = s.data(using: .utf8)!
        assert(bytes.count == 55)
        return (.bytes(bytes), "b7" + bytes.map { String(format: "%02x", $0) }.joined())
    }()

    /// 56-byte string crosses into long form: prefix is 0xb8 + 0x38
    static let stringLength56: (item: RLPItem, hex: String) = {
        let bytes = Data(repeating: 0x61, count: 56)
        return (.bytes(bytes), "b838" + bytes.map { String(format: "%02x", $0) }.joined())
    }()
}
