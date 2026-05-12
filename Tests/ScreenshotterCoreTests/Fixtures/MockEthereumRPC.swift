import Foundation
@testable import ScreenshotterCore

final class MockEthereumRPC: EthereumRPC, @unchecked Sendable {
    var canned: [String: Any] = [:]
    var receivedCalls: [(method: String, params: [Any])] = []

    func call<T: Decodable>(_ method: String, params: [Any]) async throws -> T {
        receivedCalls.append((method, params))
        guard let value = canned[method] else {
            throw NSError(domain: "MockEthereumRPC", code: 1, userInfo: [NSLocalizedDescriptionKey: "no canned response for \(method)"])
        }
        if let v = value as? T { return v }
        let data = try JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed)
        return try JSONDecoder().decode(T.self, from: data)
    }
}
