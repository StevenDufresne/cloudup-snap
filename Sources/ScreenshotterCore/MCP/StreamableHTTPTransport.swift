import Foundation

public struct StreamableHTTPTransport: MCPTransport {
    public let endpoint: URL
    public let session: URLSession

    public init(endpoint: URL, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.session = session
    }

    public func send(
        request: JSONRPCRequest,
        extraHeaders: [String: String]
    ) async throws -> JSONRPCResponse {
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        for (k, v) in extraHeaders { urlRequest.setValue(v, forHTTPHeaderField: k) }
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (bytes, response) = try await session.bytes(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? ""

        if contentType.contains("text/event-stream") {
            let stream = AsyncStream<Data> { cont in
                Task {
                    do {
                        for try await byte in bytes { cont.yield(Data([byte])) }
                        cont.finish()
                    } catch {
                        cont.finish()
                    }
                }
            }
            for try await event in SSEReader(byteStream: stream).events {
                if let data = event.data.data(using: .utf8),
                   let resp = try? JSONDecoder().decode(JSONRPCResponse.self, from: data) {
                    return resp
                }
            }
            throw URLError(.badServerResponse)
        } else {
            var data = Data()
            for try await byte in bytes { data.append(byte) }
            return try JSONDecoder().decode(JSONRPCResponse.self, from: data)
        }
    }
}
