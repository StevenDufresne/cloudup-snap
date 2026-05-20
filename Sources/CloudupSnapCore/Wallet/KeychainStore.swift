import Foundation
import Security

public protocol KeychainStore: Sendable {
    func read(account: String, service: String) throws -> Data?
    func write(_ data: Data, account: String, service: String) throws
    func delete(account: String, service: String) throws
}

public enum KeychainError: Error {
    case osStatus(OSStatus)
}

public struct MacOSKeychainStore: KeychainStore {
    public init() {}

    public func read(account: String, service: String) throws -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var ref: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &ref)
        switch status {
        case errSecSuccess:
            return ref as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.osStatus(status)
        }
    }

    public func write(_ data: Data, account: String, service: String) throws {
        let attrs: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let addStatus = SecItemAdd(attrs as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            let updateQuery: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: service,
                kSecAttrAccount: account,
            ]
            let updateAttrs: [CFString: Any] = [kSecValueData: data]
            let updateStatus = SecItemUpdate(updateQuery as CFDictionary, updateAttrs as CFDictionary)
            if updateStatus != errSecSuccess {
                throw KeychainError.osStatus(updateStatus)
            }
        } else if addStatus != errSecSuccess {
            throw KeychainError.osStatus(addStatus)
        }
    }

    public func delete(account: String, service: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.osStatus(status)
        }
    }
}
