import Foundation
import CloudupSnapCore

public enum WalletProvider {
    public static let service = "com.bongnam.cloudupsnap"
    public static let account = "default"

    /// Path to a plaintext hex private key file. Outside the repo on purpose so a
    /// stray `git add .` can't capture it. If present, it's used and no Keychain
    /// access happens — bypasses the Keychain re-prompt-on-every-rebuild issue
    /// during local development.
    public static var keyFilePath: String {
        NSHomeDirectory() + "/.cloudupsnap-wallet-key"
    }

    public static var keyFileExists: Bool {
        FileManager.default.fileExists(atPath: keyFilePath)
    }

    public static func wallet() throws -> Wallet {
        if let key = try? readKeyFile() {
            let signer = try Secp256k1Signer(privateKey: key)
            let address = EthereumAddress(uncompressedPublicKey: signer.publicKeyUncompressed)
            return Wallet(address: address, signer: signer)
        }
        return try Wallet.loadOrCreate(keychain: MacOSKeychainStore(), service: service, account: account)
    }

    /// Writes the given 32-byte private key (hex, with or without `0x` prefix)
    /// into the Keychain under the app's service/account, replacing whatever
    /// was there. Returns the resulting Wallet so callers can refresh UI.
    public static func importPrivateKey(hex: String) throws -> Wallet {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = try Data(hexString: trimmed)
        let signer = try Secp256k1Signer(privateKey: key)
        try MacOSKeychainStore().write(key, account: account, service: service)
        let address = EthereumAddress(uncompressedPublicKey: signer.publicKeyUncompressed)
        return Wallet(address: address, signer: signer)
    }

    private static func readKeyFile() throws -> Data {
        let raw = try String(contentsOfFile: keyFilePath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return try Data(hexString: raw)
    }
}
