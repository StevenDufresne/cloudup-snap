import Foundation
import CryptoSwift

public extension Data {
    /// Keccak-256 (used by Ethereum). NOT the same as SHA3-256 standardized by NIST,
    /// which has a different padding rule.
    func keccak256() -> Data {
        Data(self.sha3(.keccak256))
    }
}
