import Testing
import Foundation
@testable import ScreenshotterCore

@Test func signerProducesValidSignature() throws {
    let privKey = try Data(hexString: "0x4646464646464646464646464646464646464646464646464646464646464646")
    let signer = try Secp256k1Signer(privateKey: privKey)
    let digest = try Data(hexString: "0xdaf5a779ae972f972197303d7b574746c7ef83eadac0f2791ad23db92e4c8e53")
    let sig = try signer.signRecoverable(digest: digest)
    #expect(sig.r.count == 32)
    #expect(sig.s.count == 32)
    #expect(sig.v == 0 || sig.v == 1)
}

@Test func signerExposesPublicKey() throws {
    let privKey = try Data(hexString: "0x4646464646464646464646464646464646464646464646464646464646464646")
    let signer = try Secp256k1Signer(privateKey: privKey)
    #expect(signer.publicKeyUncompressed.count == 65)
    #expect(signer.publicKeyUncompressed[0] == 0x04)
}

@Test func signerGeneratesNewKey() throws {
    let a = try Secp256k1Signer.generate()
    let b = try Secp256k1Signer.generate()
    #expect(a.privateKey != b.privateKey)
    #expect(a.privateKey.count == 32)
}
