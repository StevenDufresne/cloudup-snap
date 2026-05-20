import Testing
import Foundation
@testable import CloudupSnapCore

@Test func jsonRPCRequestRoundTrip() throws {
    let req = JSONRPCRequest(
        id: .number(1),
        method: "tools/call",
        params: ["name": .string("quick_upload")]
    )
    let data = try JSONEncoder().encode(req)
    let decoded = try JSONDecoder().decode(JSONRPCRequest.self, from: data)
    #expect(decoded.method == "tools/call")
    #expect(decoded.params?["name"] == .string("quick_upload"))
}

@Test func jsonRPCResponseSuccessDecode() throws {
    let json = #"{"jsonrpc":"2.0","id":1,"result":{"item_id":"abc"}}"#.data(using: .utf8)!
    let resp = try JSONDecoder().decode(JSONRPCResponse.self, from: json)
    if case .success(let value) = resp.outcome {
        #expect(value.objectValue?["item_id"] == .string("abc"))
    } else {
        Issue.record("expected success outcome")
    }
}

@Test func jsonRPCResponseErrorDecode() throws {
    let json = #"{"jsonrpc":"2.0","id":1,"error":{"code":-32042,"message":"payment required","data":{"foo":"bar"}}}"#.data(using: .utf8)!
    let resp = try JSONDecoder().decode(JSONRPCResponse.self, from: json)
    if case .failure(let err) = resp.outcome {
        #expect(err.code == -32042)
        #expect(err.message == "payment required")
    } else {
        Issue.record("expected failure outcome")
    }
}

@Test func eip712ValueRoundTripsNumbersAsJSON() throws {
    // The EIP712Value encoder must emit numbers as JSON numbers, not strings.
    // Otherwise PaymentChallenge decoding will break (see Task 15).
    let original = EIP712Value.object([
        "chainId": .number("84532"),
        "name": .string("hi"),
    ])
    let data = try JSONEncoder().encode(original)
    let roundTripped = try JSONDecoder().decode(EIP712Value.self, from: data)
    #expect(roundTripped == original)
    // And the raw JSON should have a number, not a string, for chainId.
    let jsonString = String(data: data, encoding: .utf8) ?? ""
    #expect(jsonString.contains("\"chainId\":84532"))
}
