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
            let body = String(data: raw, encoding: .utf8) ?? "<\(raw.count) bytes binary>"
            let excerpt = body.count > 240 ? String(body.prefix(240)) + "…" : body
            // Dump everything we have to stderr so the app.log captures it.
            // The body excerpt above can be empty when the server replies with
            // 500 + no body, which hides whether it's nginx vs upstream vs WAF.
            // The headers and request-body summary make that distinguishable.
            // Strip the big base64 payload from `content_base64` so the
            // diagnostic stays readable and the _meta payment payload (which
            // sits later in the JSON) actually makes it into the excerpt.
            var reqBodyStr = String(data: urlRequest.httpBody ?? Data(), encoding: .utf8) ?? "<binary>"
            if let range = reqBodyStr.range(of: #""content_base64":""#),
               let endQuote = reqBodyStr.range(of: "\"", range: range.upperBound..<reqBodyStr.endIndex) {
                let length = reqBodyStr.distance(from: range.upperBound, to: endQuote.lowerBound)
                reqBodyStr.replaceSubrange(range.upperBound..<endQuote.lowerBound,
                                            with: "<\(length) base64 chars>")
            }
            let reqExcerpt = reqBodyStr.count > 1800 ? String(reqBodyStr.prefix(1800)) + "…" : reqBodyStr
            let dump = """
            [MCP-HTTP] non-2xx response
              status=\(http.statusCode) content-type=\(contentType) content-length=\(raw.count)
              endpoint=\(endpoint.absoluteString)
              headers=\(headers)
              response-body=\(body)
              request-body=\(reqExcerpt)

            """
            FileHandle.standardError.write(dump.data(using: .utf8) ?? Data())
            // Mirror to app.log (same pattern as Wallet's x402-sign logging)
            // so the user can paste the diagnostic without needing to attach
            // stderr.
            let logPath = NSHomeDirectory() + "/Library/Logs/CloudupSnap/app.log"
            if let fh = FileHandle(forWritingAtPath: logPath),
               let data = dump.data(using: .utf8) {
                fh.seekToEndOfFile()
                fh.write(data)
                try? fh.close()
            }
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
