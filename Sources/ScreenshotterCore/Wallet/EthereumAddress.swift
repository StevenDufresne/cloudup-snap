import Foundation

public enum EthereumAddressError: Error {
    case badPublicKeyLength
}

public struct EthereumAddress: Equatable, Hashable {
    /// 20 raw bytes.
    public let bytes: Data

    public init(bytes: Data) {
        precondition(bytes.count == 20)
        self.bytes = bytes
    }

    /// Derive from a 65-byte uncompressed secp256k1 public key (0x04 || X || Y).
    public init(uncompressedPublicKey: Data) {
        precondition(uncompressedPublicKey.count == 65 && uncompressedPublicKey[0] == 0x04)
        let xy = uncompressedPublicKey.suffix(64)
        let hash = Data(xy).keccak256()
        self.bytes = hash.suffix(20)
    }

    public init(uncompressedPublicKeyOrThrow pub: Data) throws {
        guard pub.count == 65, pub[0] == 0x04 else { throw EthereumAddressError.badPublicKeyLength }
        self.init(uncompressedPublicKey: pub)
    }

    /// Lowercase 0x-prefixed hex string.
    public func hexString() -> String {
        bytes.hexEncodedString(prefix: true)
    }
}
