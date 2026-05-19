import Foundation
import ScreenshotterCore

public enum WalletProvider {
    public static let service = "com.bongnam.screenshotter"
    public static let account = "default"

    /// Path to a plaintext hex private key file. Outside the repo on purpose so a
    /// stray `git add .` can't capture it. If present, it's used and no Keychain
    /// access happens — bypasses the Keychain re-prompt-on-every-rebuild issue
    /// during local development.
    public static var keyFilePath: String {
        NSHomeDirectory() + "/.screenshotter-wallet-key"
    }

    public static func wallet() throws -> Wallet {
        if let key = try? readKeyFile() {
            let signer = try Secp256k1Signer(privateKey: key)
            let address = EthereumAddress(uncompressedPublicKey: signer.publicKeyUncompressed)
            return Wallet(address: address, signer: signer)
        }
        return try Wallet.loadOrCreate(keychain: MacOSKeychainStore(), service: service, account: account)
    }

    private static func readKeyFile() throws -> Data {
        let raw = try String(contentsOfFile: keyFilePath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return try Data(hexString: raw)
    }
}
