import Testing
import Foundation
@testable import ScreenshotterCore

@Test func mcpClientCallsToolAndDecodesResult() async throws {
    let transport = MockMCPTransport()
    let resultJSON = #"{"jsonrpc":"2.0","id":1,"result":{"item_id":"abc","share_url":"https://x.test/abc"}}"#
    transport.queuedResponses = [
        try JSONDecoder().decode(JSONRPCResponse.self, from: resultJSON.data(using: .utf8)!)
    ]
    let client = MCPClient(transport: transport)
    let result = try await client.callTool(name: "quick_upload", arguments: [
        "filename": .string("x.png")
    ])
    #expect(result.objectValue?["item_id"] == .string("abc"))
    #expect(transport.receivedRequests.count == 1)
    #expect(transport.receivedRequests[0].request.method == "tools/call")
}

@Test func mcpClientPassesMetaInParams() async throws {
    let transport = MockMCPTransport()
    let resultJSON = #"{"jsonrpc":"2.0","id":1,"result":{"ok":true}}"#
    transport.queuedResponses = [
        try JSONDecoder().decode(JSONRPCResponse.self, from: resultJSON.data(using: .utf8)!)
    ]
    let client = MCPClient(transport: transport)
    _ = try await client.callTool(
        name: "quick_upload",
        arguments: ["filename": .string("x.png")],
        meta: ["org.paymentauth/credential": .object([
            "method": .string("erc20-usdc-base-sepolia"),
            "settlement_tx_hash": .string("0xabc"),
        ])]
    )
    let req = transport.receivedRequests[0].request
    let params = req.params
    #expect(params?["_meta"]?.objectValue?["org.paymentauth/credential"] != nil)
    #expect(params?["arguments"]?.objectValue?["filename"] == .string("x.png"))
}

@Test func mcpClientThrowsJSONRPCError() async throws {
    let transport = MockMCPTransport()
    let errJSON = #"{"jsonrpc":"2.0","id":1,"error":{"code":-32042,"message":"payment required"}}"#
    transport.queuedResponses = [
        try JSONDecoder().decode(JSONRPCResponse.self, from: errJSON.data(using: .utf8)!)
    ]
    let client = MCPClient(transport: transport)
    await #expect(throws: JSONRPCError.self) {
        _ = try await client.callTool(name: "quick_upload", arguments: [:])
    }
}
