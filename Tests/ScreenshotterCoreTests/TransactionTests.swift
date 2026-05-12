import Testing
import Foundation
@testable import ScreenshotterCore

@Test func eip1559TransactionStructureHasCorrectFields() throws {
    let priv = try Data(hexString: TxSigningVectors.testPrivateKeyHex)
    let signer = try Secp256k1Signer(privateKey: priv)
    let to = try Data(hexString: "0xc5f06701bd664159620f1a83a64a57ebcef9151b")

    let tx = EIP1559Transaction(
        chainId: TxSigningVectors.chainIdBaseSepolia,
        nonce: 0,
        maxPriorityFeePerGas: 1_000_000_000,
        maxFeePerGas: 2_000_000_000,
        gasLimit: 21_000,
        to: to,
        value: 1,
        data: Data()
    )
    let signed = try tx.sign(with: signer)
    #expect(signed.rawTransaction.first == 0x02)
    #expect(signed.transactionHash.count == 32)
}

@Test func eip1559MatchesViemReference() throws {
    let priv = try Data(hexString: TxSigningVectors.testPrivateKeyHex)
    let signer = try Secp256k1Signer(privateKey: priv)
    let to = try Data(hexString: "0xc5f06701bd664159620f1a83a64a57ebcef9151b")
    let tx = EIP1559Transaction(
        chainId: TxSigningVectors.chainIdBaseSepolia,
        nonce: 0,
        maxPriorityFeePerGas: 1_000_000_000,
        maxFeePerGas: 2_000_000_000,
        gasLimit: 21_000,
        to: to,
        value: 1,
        data: Data()
    )
    let signed = try tx.sign(with: signer)
    #expect(signed.rawTransaction.hexEncodedString(prefix: true) == TxSigningVectors.baseSepoliaSimpleTransferRawTx)
}
