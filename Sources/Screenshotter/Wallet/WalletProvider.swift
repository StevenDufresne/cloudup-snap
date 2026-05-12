import Foundation
import ScreenshotterCore

public enum WalletProvider {
    public static let service = "com.bongnam.screenshotter"
    public static let account = "default"

    public static func wallet() throws -> Wallet {
        try Wallet.loadOrCreate(keychain: MacOSKeychainStore(), service: service, account: account)
    }
}
