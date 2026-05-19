import Foundation

/// Thrown when the HTTP layer rejected the request before the MCP server saw
/// it — most often nginx's `client_max_body_size` (413) or a gateway timeout
/// (502/504). Carries the status and a short body excerpt so the upper layer
/// can produce a useful error instead of a JSON-decode failure.
public struct HTTPTransportError: Error, CustomStringConvertible {
    public let status: Int
    public let bodyExcerpt: String
    public var description: String {
        "HTTP \(status) — \(bodyExcerpt)"
    }
}

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
    ) async throws -> MCPSendResult {
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
        let headers: [String: String] = http.allHeaderFields.reduce(into: [:]) { acc, kv in
            if let k = kv.key as? String, let v = kv.value as? String { acc[k] = v }
        }

        // Non-2xx with an HTML body almost always means a proxy-layer error
        // (413, 502, 504, etc.) rather than a JSON-RPC response. Surface it
        // with the status and a short body excerpt so callers can show
        // something actionable. We deliberately do NOT translate 4xx codes
        // with JSON bodies — those go through the normal JSON-RPC error path.
        if !(200..<300).contains(http.statusCode) && !contentType.contains("application/json") && !contentType.contains("text/event-stream") {
            var raw = Data()
            for try await byte in bytes { raw.append(byte) }
            let body = String(data: raw, encoding: .utf8) ?? "<\(raw.count) bytes>"
            let excerpt = body.count > 240 ? String(body.prefix(240)) + "…" : body
            throw HTTPTransportError(status: http.statusCode, bodyExcerpt: excerpt)
        }

        if contentType.contains("text/event-stream") {
            let stream = AsyncStream<Data> { cont in
                Task {
                    for try await byte in bytes { cont.yield(Data([byte])) }
                    cont.finish()
                }
            }
            for try await event in SSEReader(byteStream: stream).events {
                if let data = event.data.data(using: .utf8),
                   let resp = try? JSONDecoder().decode(JSONRPCResponse.self, from: data) {
                    return MCPSendResult(response: resp, responseHeaders: headers)
                }
            }
            throw URLError(.badServerResponse)
        } else {
            var data = Data()
            for try await byte in bytes { data.append(byte) }
            let resp = try JSONDecoder().decode(JSONRPCResponse.self, from: data)
            return MCPSendResult(response: resp, responseHeaders: headers)
        }
    }
}
