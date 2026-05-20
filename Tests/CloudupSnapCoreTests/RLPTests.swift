import Testing
import Foundation
@testable import CloudupSnapCore

@Test func rlpEncodesPrimitiveVectors() {
    for (description, item, expected) in RLPVectors.primitives {
        let encoded = RLP.encode(item).hexEncodedString()
        #expect(encoded == expected, "RLP encoding failed: \(description) — got \(encoded), expected \(expected)")
    }
}

@Test func rlpEncodesLongString() {
    let (item, expected) = RLPVectors.stringLength55
    #expect(RLP.encode(item).hexEncodedString() == expected)
}

@Test func rlpEncodesVeryLongString() {
    let (item, expected) = RLPVectors.stringLength56
    #expect(RLP.encode(item).hexEncodedString() == expected)
}

@Test func rlpUintHasNoLeadingZeros() {
    #expect(RLP.encode(.uint(1)).hexEncodedString() == "01")
    #expect(RLP.encode(.uint(0)).hexEncodedString() == "80")
}
