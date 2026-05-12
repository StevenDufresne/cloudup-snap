import Foundation

enum TxSigningVectors {
    /// Generated with viem 2.48 (chainId=84532 Base Sepolia, nonce=0,
    /// maxPriorityFeePerGas=1 gwei, maxFeePerGas=2 gwei, gas=21000,
    /// to=0xc5f06701bd664159620f1a83a64a57ebcef9151b, value=1, data=0x, accessList=[]).
    /// Private key: 0xac09…ff80 (hardhat test key #0; never real funds).
    static let baseSepoliaSimpleTransferRawTx =
        "0x02f86d83014a3480843b9aca00847735940082520894c5f06701bd664159620f1a83a64a57ebcef9151b0180c001a00b79e4fb63f61c145df7dd043e68c048a1e42384db9820d5d282effed63b18dba061b1f764ad5718a75f7ba3fd031e5c323d18051f902a8b762d8bf75ebaea4aa1"

    static let chainIdBaseSepolia: UInt64 = 84532
    static let testPrivateKeyHex =
        "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
}
