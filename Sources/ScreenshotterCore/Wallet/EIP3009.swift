import Foundation

/// EIP-712 typed-data hashing for ERC-20 EIP-3009 `TransferWithAuthorization`.
/// Used by x402 v1: the client signs this digest off-chain; the server submits
/// the meta-transaction on-chain.
///
/// Reference: https://eips.ethereum.org/EIPS/eip-3009
public enum EIP3009 {

    /// Hard-coded EIP-712 type strings → typeHash inputs.
    /// Concatenating these and keccak'ing gives the typeHash for `EIP712Domain`
    /// and `TransferWithAuthorization` respectively.
    public static let domainType =
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    public static let transferAuthType =
        "TransferWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)"

    /// Compute the 32-byte digest that the wallet signs.
    ///
    /// - Parameters:
    ///   - domainName: from challenge `extra.name` (e.g. "USDC")
    ///   - domainVersion: from challenge `extra.version` (e.g. "2")
    ///   - chainId: EIP-155 chain id (84532 for Base Sepolia)
    ///   - verifyingContract: ERC-20 token contract (20 bytes)
    ///   - from: payer's address (20 bytes)
    ///   - to: recipient (20 bytes)
    ///   - value: token amount in raw units, 32-byte big-endian
    ///   - validAfter: unix timestamp, 0 = always valid (will be zero-padded)
    ///   - validBefore: unix timestamp (will be zero-padded)
    ///   - nonce: random 32 bytes
    public static func digest(
        domainName: String,
        domainVersion: String,
        chainId: UInt64,
        verifyingContract: Data,
        from: Data,
        to: Data,
        value: Data,
        validAfter: UInt64,
        validBefore: UInt64,
        nonce: Data
    ) -> Data {
        precondition(verifyingContract.count == 20)
        precondition(from.count == 20)
        precondition(to.count == 20)
        precondition(nonce.count == 32)

        // ── EIP712Domain hash ──
        let domainTypeHash = domainType.data(using: .utf8)!.keccak256()
        let nameHash = domainName.data(using: .utf8)!.keccak256()
        let versionHash = domainVersion.data(using: .utf8)!.keccak256()
        var domainData = Data()
        domainData.append(domainTypeHash)
        domainData.append(nameHash)
        domainData.append(versionHash)
        domainData.append(leftPad(uint64ToData(chainId), to: 32))
        domainData.append(leftPad(verifyingContract, to: 32))
        let domainSeparator = domainData.keccak256()

        // ── TransferWithAuthorization struct hash ──
        let structTypeHash = transferAuthType.data(using: .utf8)!.keccak256()
        var structData = Data()
        structData.append(structTypeHash)
        structData.append(leftPad(from, to: 32))
        structData.append(leftPad(to, to: 32))
        structData.append(leftPad(value, to: 32))
        structData.append(leftPad(uint64ToData(validAfter), to: 32))
        structData.append(leftPad(uint64ToData(validBefore), to: 32))
        structData.append(nonce)  // already 32 bytes
        let structHash = structData.keccak256()

        // ── Final digest: keccak256(0x1901 || domainSeparator || structHash) ──
        var preimage = Data([0x19, 0x01])
        preimage.append(domainSeparator)
        preimage.append(structHash)
        return preimage.keccak256()
    }

    // MARK: - Helpers

    /// Left-pads `data` with zero bytes to `width`. If the data is already at
    /// least `width` bytes, returns the trailing `width` bytes.
    static func leftPad(_ data: Data, to width: Int) -> Data {
        if data.count >= width {
            return data.suffix(width)
        }
        return Data(count: width - data.count) + data
    }

    /// Big-endian byte representation of a UInt64 (8 bytes, with leading zeros).
    static func uint64ToData(_ value: UInt64) -> Data {
        var result = Data(count: 8)
        for i in 0..<8 {
            result[7 - i] = UInt8(truncatingIfNeeded: value >> (i * 8))
        }
        return result
    }
}
