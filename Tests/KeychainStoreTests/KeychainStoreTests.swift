import XCTest
@testable import CloudupSnapCore

final class KeychainStoreTests: XCTestCase {
    let service = "com.bongnam.cloudupsnap.tests"
    let account = "integration-test-\(UUID().uuidString)"
    let sut = MacOSKeychainStore()

    override func setUp() async throws {
        guard ProcessInfo.processInfo.environment["CLOUDUPSNAP_KEYCHAIN_TESTS"] == "1" else {
            throw XCTSkip("Set CLOUDUPSNAP_KEYCHAIN_TESTS=1 to run Keychain integration tests.")
        }
        try? sut.delete(account: account, service: service)
    }

    override func tearDown() async throws {
        try? sut.delete(account: account, service: service)
    }

    func testRoundTrip() throws {
        let data = Data([0xde, 0xad, 0xbe, 0xef])
        try sut.write(data, account: account, service: service)
        let read = try sut.read(account: account, service: service)
        XCTAssertEqual(read, data)
    }

    func testOverwrite() throws {
        try sut.write(Data([0x01]), account: account, service: service)
        try sut.write(Data([0x02]), account: account, service: service)
        XCTAssertEqual(try sut.read(account: account, service: service), Data([0x02]))
    }

    func testDelete() throws {
        try sut.write(Data([0x01]), account: account, service: service)
        try sut.delete(account: account, service: service)
        XCTAssertNil(try sut.read(account: account, service: service))
    }
}
