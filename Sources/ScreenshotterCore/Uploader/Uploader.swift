import Foundation

public struct Uploader: Sendable {
    public let mcp: MCPClient
    public let payment: PaymentClient

    public init(mcp: MCPClient, payment: PaymentClient) {
        self.mcp = mcp
        self.payment = payment
    }

    /// Multi-step upload for files too large to inline-base64 through the
    /// MCP transport: `begin_upload` returns a presigned S3 URL, the client
    /// PUTs raw bytes, then `complete_upload` finalizes and returns share URLs.
    /// Use this for video recordings (and any future large payload). Same
    /// x402-payment behavior as `upload` — either call may surface a challenge.
    public func uploadLarge(data: Data, filename: String, mime: String) async throws -> URL {
        let beginArgs: [String: EIP712Value] = [
            "filename": .string(filename),
            "mime": .string(mime),
            "size_bytes": .number(String(data.count)),
        ]
        let beginResult = try await callToolWithX402Retry(name: "begin_upload", arguments: beginArgs)
        let (uploadID, s3URL) = try extractBeginUpload(from: beginResult)
        try await s3Put(url: s3URL, data: data, mime: mime)

        let completeArgs: [String: EIP712Value] = [
            "upload_id": .string(uploadID),
        ]
        let completeResult = try await callToolWithX402Retry(name: "complete_upload", arguments: completeArgs)
        return try extractShareURL(from: completeResult)
    }

    /// Single-step inline upload — fast path for small payloads (screenshots).
    public func upload(data: Data, filename: String, mime: String) async throws -> URL {
        let args: [String: EIP712Value] = [
            "filename": .string(filename),
            "mime": .string(mime),
            "content_base64": .string(data.base64EncodedString()),
        ]
        // First attempt — no payment yet.
        do {
            let result = try await mcp.callTool(name: "quick_upload", arguments: args)
            do {
                return try extractShareURL(from: result)
            } catch let req as X402ChallengeThrown {
                // x402 MCP transport carries the signed payload in the
                // JSON-RPC body as `params._meta["x402/payment"]`, NOT as an
                // HTTP header. (HTTP `X-PAYMENT` is the http-transport variant
                // — wrong for an MCP server.) See coinbase/x402
                // specs/transports-v1/mcp.md.
                let signed = try await payment.settleX402(req.requirements)
                #if DEBUG
                FileHandle.standardError.write("[Uploader] x402 _meta payment attached\n".data(using: .utf8)!)
                #endif
                let retry = try await mcp.callTool(
                    name: "quick_upload",
                    arguments: args,
                    meta: ["x402/payment": signed.asEIP712Value]
                )
                do {
                    return try extractShareURL(from: retry)
                } catch is X402ChallengeThrown {
                    // Cloudup re-sent the challenge → our signature was
                    // rejected. Common causes: wrong EIP-712 domain (name /
                    // version), insufficient on-chain USDC, replayed nonce.
                    throw PaymentError.other("Cloudup rejected our x402 payment. The signed authorization didn't validate — verify the wallet has enough USDC, then try again.")
                }
            }
        } catch let err as JSONRPCError where payment.isPaymentRequired(err) {
            // Legacy `mpp-remote` -32042 challenge path. Still supported.
            let payload = try payment.extractPayload(from: err)
            guard let challenge = payload.challenges.first else {
                throw PaymentError.malformedChallenge("empty challenges array")
            }
            let credential = try await payment.settle(challenge: challenge)
            let result = try await mcp.callTool(
                name: "quick_upload",
                arguments: args,
                meta: ["org.paymentauth/credential": credential.asEIP712Value]
            )
            return try extractShareURL(from: result)
        }
    }

    /// Sentinel thrown when `extractShareURL` recognises an x402 challenge
    /// embedded in the tool result. Caught one level up to sign + retry.
    struct X402ChallengeThrown: Error {
        let requirements: X402PaymentRequirements
    }

    /// Look for an x402 v1 payment challenge embedded in an MCP tool result's
    /// `content[].text`. Returns nil if the result is a normal success or any
    /// other failure shape.
    private func findX402Challenge(in value: EIP712Value) -> X402PaymentRequirements? {
        guard case .object(let obj) = value,
              case .array(let content) = obj["content"] ?? .null else {
            return nil
        }
        for item in content {
            if case .object(let part) = item,
               case .string(let text) = part["text"] ?? .null,
               let req = parseX402Challenge(from: text) {
                return req
            }
        }
        return nil
    }

    /// Call any MCP tool, detect an x402 challenge in the response, sign +
    /// retry once if present. Returns the (post-retry) result on success;
    /// throws PaymentError if the retry also re-challenges.
    private func callToolWithX402Retry(name: String, arguments: [String: EIP712Value]) async throws -> EIP712Value {
        let first = try await mcp.callTool(name: name, arguments: arguments)
        guard let req = findX402Challenge(in: first) else {
            return first
        }
        let signed = try await payment.settleX402(req)
        let retry = try await mcp.callTool(
            name: name, arguments: arguments,
            meta: ["x402/payment": signed.asEIP712Value]
        )
        if findX402Challenge(in: retry) != nil {
            throw PaymentError.other("Cloudup rejected our x402 payment. The signed authorization didn't validate — verify the wallet has enough USDC, then try again.")
        }
        return retry
    }

    /// Pull `upload_id` and a presigned PUT URL out of a `begin_upload` result.
    /// The tool wraps its JSON in `content[0].text` per the MCP convention.
    /// We also accept top-level fields as a fallback in case the server stops
    /// double-wrapping in a future version.
    private func extractBeginUpload(from value: EIP712Value) throws -> (uploadID: String, s3URL: URL) {
        guard case .object(let obj) = value else {
            throw PaymentError.other("begin_upload: unexpected response shape — \(preview(of: value))")
        }
        let inner: [String: EIP712Value]?
        if case .array(let content) = obj["content"] ?? .null {
            inner = content.lazy.compactMap { item -> [String: EIP712Value]? in
                guard case .object(let part) = item,
                      case .string(let text) = part["text"] ?? .null,
                      let data = text.data(using: .utf8),
                      let decoded = try? JSONDecoder().decode(EIP712Value.self, from: data),
                      case .object(let o) = decoded
                else { return nil }
                return o
            }.first
        } else {
            inner = obj
        }
        guard let inner else {
            throw PaymentError.other("begin_upload: no parseable content — \(preview(of: value))")
        }
        // The server's field naming isn't strictly nailed down in the public
        // tool description, so accept a few common aliases.
        let idCandidates = ["upload_id", "uploadId", "id"]
        let urlCandidates = ["s3_url", "presigned_url", "put_url", "url"]
        let uploadID = idCandidates.compactMap { inner[$0]?.stringValue }.first
        let s3URL = urlCandidates.compactMap { inner[$0]?.stringValue }.compactMap(URL.init(string:)).first
        guard let uploadID, let s3URL else {
            throw PaymentError.other("begin_upload: missing upload_id or s3_url. Raw: \(preview(of: value))")
        }
        return (uploadID, s3URL)
    }

    /// Out-of-band raw PUT to the presigned S3 URL. Used by `uploadLarge`.
    private func s3Put(url: URL, data: Data, mime: String) async throws {
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue(mime, forHTTPHeaderField: "Content-Type")
        let (body, response) = try await URLSession.shared.upload(for: req, from: data)
        guard let http = response as? HTTPURLResponse else {
            throw PaymentError.other("S3 PUT: no HTTP response")
        }
        if !(200..<300).contains(http.statusCode) {
            let text = String(data: body, encoding: .utf8) ?? "<\(body.count) bytes>"
            let excerpt = text.count > 240 ? String(text.prefix(240)) + "…" : text
            throw PaymentError.other("S3 PUT failed: HTTP \(http.statusCode) — \(excerpt)")
        }
    }

    private func extractShareURL(from value: EIP712Value) throws -> URL {
        guard case .object(let obj) = value else {
            let snippet = preview(of: value)
            throw PaymentError.other("Cloudup returned an unexpected response (not an object). Got: \(snippet)")
        }
        // MCP tools/call wraps the tool's actual result in a `content` array,
        // typically `[{type: "text", text: "<json>"}]`. Parse the inner text as JSON
        // if we see that shape; otherwise look for share_url directly.
        if case .array(let content) = obj["content"] ?? .null {
            for item in content {
                if case .object(let part) = item,
                   case .string(let text) = part["text"] ?? .null,
                   let data = text.data(using: .utf8),
                   let inner = try? JSONDecoder().decode(EIP712Value.self, from: data),
                   case .object(let innerObj) = inner,
                   case .string(let s) = innerObj["share_url"] ?? .null,
                   let url = URL(string: s) {
                    return url
                }
            }
            // Pull text parts out of the content array. Cloudup sometimes
            // returns these as an x402 v1 payment challenge or as an error
            // payload — recognise and translate to typed errors before falling
            // back to the verbatim message.
            let textParts = content.compactMap { item -> String? in
                guard case .object(let part) = item,
                      case .string(let t) = part["text"] ?? .null else { return nil }
                return t
            }
            // x402 v1 payment-required challenge — sign + retry happens one
            // level up. Throw a sentinel the caller catches.
            for text in textParts {
                if let req = parseX402Challenge(from: text) {
                    throw X402ChallengeThrown(requirements: req)
                }
            }
            if !textParts.isEmpty {
                throw PaymentError.other("Cloudup didn't return a share URL. Server said: \(textParts.joined(separator: " | "))")
            }
            throw PaymentError.other("Cloudup returned an empty response. Raw: \(preview(of: value))")
        }
        if case .string(let s) = obj["share_url"] ?? .null, let url = URL(string: s) {
            return url
        }
        throw PaymentError.other("Cloudup response missing share_url. Raw: \(preview(of: value))")
    }

    /// Compact preview of an EIP712Value for error messages. Caps at ~400 chars
    /// so a giant response doesn't drown an alert dialog.
    private func preview(of value: EIP712Value) -> String {
        if let data = try? JSONEncoder().encode(value),
           let str = String(data: data, encoding: .utf8) {
            return str.count > 400 ? String(str.prefix(400)) + "…" : str
        }
        return "\(value)"
    }

}
