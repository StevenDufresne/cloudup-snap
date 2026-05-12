import Foundation
import ScreenshotterCore

@main
struct CLI {
    static func main() async {
        do {
            try await run()
        } catch {
            FileHandle.standardError.write("error: \(error)\n".data(using: .utf8)!)
            exit(1)
        }
    }

    static func run() async throws {
        let args = CommandLine.arguments
        if args.count >= 2, args[1] == "address" {
            let wallet = try defaultWallet()
            print(wallet.address.hexString())
            return
        }
        guard args.count >= 3, args[1] == "upload" else {
            print("usage: screenshotter-cli upload <path>")
            print("       screenshotter-cli address")
            exit(2)
        }
        let path = args[2]
        let fileURL = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: fileURL)
        let filename = fileURL.lastPathComponent
        let mime = mimeType(for: fileURL.pathExtension)

        let wallet = try defaultWallet()
        let env = ProcessInfo.processInfo.environment
        let rpcEndpoint = URL(string: env["BASE_SEPOLIA_RPC"] ?? "https://sepolia.base.org")!
        let mcpEndpoint = URL(string: env["MCP_ENDPOINT"] ?? "https://api.stage-cloudup.com/mcp/public")!
        let rpc = HTTPEthereumRPC(endpoint: rpcEndpoint)
        let payment = PaymentClient(
            wallet: wallet,
            rpc: rpc,
            capUSD: Decimal(string: "0.50")!,
            receiptPoll: ReceiptPollPolicy(interval: 2.0, timeout: 120.0)
        )
        let transport = StreamableHTTPTransport(endpoint: mcpEndpoint)
        let mcp = MCPClient(transport: transport)
        let uploader = Uploader(mcp: mcp, payment: payment)

        FileHandle.standardError.write(
            "uploading \(filename) (\(data.count) bytes) from \(wallet.address.hexString())\n"
                .data(using: .utf8)!
        )
        let url = try await uploader.upload(data: data, filename: filename, mime: mime)
        print(url.absoluteString)
    }

    static func defaultWallet() throws -> Wallet {
        try Wallet.loadOrCreate(
            keychain: MacOSKeychainStore(),
            service: "com.bongnam.screenshotter",
            account: "default"
        )
    }

    static func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "svg": return "image/svg+xml"
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        default: return "application/octet-stream"
        }
    }
}
