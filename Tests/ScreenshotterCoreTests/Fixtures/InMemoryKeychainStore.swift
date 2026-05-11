import Foundation
@testable import ScreenshotterCore

final class InMemoryKeychainStore: KeychainStore, @unchecked Sendable {
    private var storage: [String: Data] = [:]
    private let lock = NSLock()

    private func key(account: String, service: String) -> String { "\(service)/\(account)" }

    func read(account: String, service: String) throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        return storage[key(account: account, service: service)]
    }
    func write(_ data: Data, account: String, service: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage[key(account: account, service: service)] = data
    }
    func delete(account: String, service: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage.removeValue(forKey: key(account: account, service: service))
    }
}
