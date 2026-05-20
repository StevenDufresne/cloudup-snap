import Testing
import Foundation
@testable import CloudupSnapCore

@Test func addressFromKnownPrivateKey() throws {
    // Vitalik's test private key (publicly known, never for real funds):
    // priv 0x4646464646464646464646464646464646464646464646464646464646464646
    // addr 0x9d8a62f656a8d1615c1294fd71e9cfb3e4855a4f
    let priv = try Data(hexString: "0x4646464646464646464646464646464646464646464646464646464646464646")
    let signer = try Secp256k1Signer(privateKey: priv)
    let address = EthereumAddress(uncompressedPublicKey: signer.publicKeyUncompressed)
    #expect(address.hexString() == "0x9d8a62f656a8d1615c1294fd71e9cfb3e4855a4f")
}

@Test func addressRejectsBadPublicKey() {
    #expect(throws: EthereumAddressError.self) {
        _ = try EthereumAddress(uncompressedPublicKeyOrThrow: Data([0x04, 0x01, 0x02]))
    }
}
