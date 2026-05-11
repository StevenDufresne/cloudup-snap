import Foundation
import P256K

public struct RecoverableSignature: Equatable {
    public let r: Data        // 32 bytes
    public let s: Data        // 32 bytes
    public let v: UInt8       // recovery id: 0 or 1
}

public enum Secp256k1Error: Error {
    case invalidPrivateKeyLength
    case signingFailed
    case keyGenerationFailed
}

public struct Secp256k1Signer {
    public let privateKey: Data            // 32 bytes
    public let publicKeyUncompressed: Data // 65 bytes (0x04 || X || Y)

    public init(privateKey: Data) throws {
        guard privateKey.count == 32 else { throw Secp256k1Error.invalidPrivateKeyLength }
        let key = try P256K.Signing.PrivateKey(dataRepresentation: privateKey, format: .uncompressed)
        self.privateKey = privateKey
        // uncompressedRepresentation always returns 65 bytes (0x04 prefix + 32 X + 32 Y)
        self.publicKeyUncompressed = key.publicKey.uncompressedRepresentation
    }

    public static func generate() throws -> Secp256k1Signer {
        let key = try P256K.Signing.PrivateKey(format: .uncompressed)
        return try Secp256k1Signer(privateKey: Data(key.dataRepresentation))
    }

    public func signRecoverable(digest: Data) throws -> RecoverableSignature {
        guard digest.count == 32 else { throw Secp256k1Error.signingFailed }
        let key = try P256K.Recovery.PrivateKey(dataRepresentation: privateKey)
        // Wrap the raw 32-byte digest as a HashDigest (Digest protocol conformance)
        // so the recovery signing API accepts it without hashing again.
        let hashDigest = HashDigest(Array(digest))
        let signature = key.signature(for: hashDigest)
        // compactRepresentation gives us 64-byte (r||s) and a separate recoveryId
        let compact = signature.compactRepresentation
        let rs = compact.signature  // 64 bytes: r (0..<32) || s (32..<64)
        guard rs.count == 64 else { throw Secp256k1Error.signingFailed }
        let v = UInt8(compact.recoveryId & 0xFF)
        return RecoverableSignature(
            r: rs.subdata(in: 0..<32),
            s: rs.subdata(in: 32..<64),
            v: v
        )
    }
}
