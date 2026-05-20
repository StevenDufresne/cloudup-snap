import Testing
import Foundation
@testable import CloudupSnapCore

@Test func hexEncodingRoundTrip() throws {
    let data = Data([0x00, 0xff, 0xab, 0xcd])
    #expect(data.hexEncodedString() == "00ffabcd")
    #expect(data.hexEncodedString(prefix: true) == "0x00ffabcd")
    #expect(try Data(hexString: "0x00ffabcd") == data)
    #expect(try Data(hexString: "00FFABCD") == data)
}

@Test func hexEncodingRejectsInvalid() {
    #expect(throws: HexError.self) { try Data(hexString: "0xZZ") }
    #expect(throws: HexError.self) { try Data(hexString: "abc") } // odd length
}

@Test func keccak256KnownVectors() throws {
    // Empty input vector
    let empty = Data().keccak256()
    #expect(empty.hexEncodedString() == "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470")

    // ASCII "abc" vector
    let abc = "abc".data(using: .utf8)!.keccak256()
    #expect(abc.hexEncodedString() == "4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45")
}
