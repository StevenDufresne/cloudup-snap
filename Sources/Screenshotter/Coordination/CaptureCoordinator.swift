import AppKit
import Foundation
import ScreenshotterCore
@preconcurrency import ScreenCaptureKit
import CoreGraphics

@MainActor
public final class CaptureCoordinator {
    private let capture = CaptureService()
    private let regionOverlay = RegionSelectionOverlay()
    private let editor = AnnotationEditor()
    private let clipboard = ClipboardService()
    private let funding = FundingPanel()
    private var inFlight = false

    public init() {}

    public func startCapture(mode: CaptureMode) {
        guard !inFlight else { return }
        inFlight = true
        switch mode {
        case .region:
            regionOverlay.present { [weak self] selectedRect in
                guard let self else { return }
                guard let rect = selectedRect else { self.inFlight = false; return }
                Task { await self.captureRegionAndEdit(rect: rect) }
            }
        case .fullScreen:
            Task { await self.captureFullAndEdit() }
        case .window:
            Task { await self.captureWindowAndEdit() }
        }
    }

    private func captureRegionAndEdit(rect: CGRect) async {
        do {
            let full = try await capture.captureFullScreen()
            let scale = NSScreen.main?.backingScaleFactor ?? 2.0
            let scaled = CGRect(x: rect.origin.x * scale, y: rect.origin.y * scale,
                                width: rect.width * scale, height: rect.height * scale)
            guard let cropped = full.cropping(to: scaled) else { inFlight = false; return }
            openEditor(with: cropped)
        } catch {
            await NotificationService.shared.toast(title: "Capture failed", body: "\(error)")
            inFlight = false
        }
    }

    private func captureFullAndEdit() async {
        do {
            let full = try await capture.captureFullScreen()
            openEditor(with: full)
        } catch {
            await NotificationService.shared.toast(title: "Capture failed", body: "\(error)")
            inFlight = false
        }
    }

    private func captureWindowAndEdit() async {
        do {
            let content = try await capture.shareableContent()
            guard let win = content.windows.first(where: { $0.isOnScreen && $0.owningApplication?.applicationName != "Screenshotter" }) else {
                inFlight = false; return
            }
            let img = try await capture.captureWindow(win)
            openEditor(with: img)
        } catch {
            await NotificationService.shared.toast(title: "Capture failed", body: "\(error)")
            inFlight = false
        }
    }

    private func openEditor(with background: CGImage) {
        editor.present(background: background) { [weak self] doc in
            guard let self else { return }
            guard let doc = doc else { self.inFlight = false; return }
            Task { await self.flattenAndUpload(doc: doc) }
        }
    }

    private func flattenAndUpload(doc: AnnotationDocument) async {
        do {
            let png = try Renderer.flatten(doc)
            let wallet = try WalletProvider.wallet()
            let rpc = HTTPEthereumRPC(endpoint: URL(string: "https://sepolia.base.org")!)
            let payment = PaymentClient(
                wallet: wallet, rpc: rpc,
                capUSD: Decimal(string: "0.50")!,
                receiptPoll: ReceiptPollPolicy(interval: 2.0, timeout: 120.0)
            )
            let mcp = MCPClient(transport: StreamableHTTPTransport(
                endpoint: URL(string: "https://api.stage-cloudup.com/mcp/public")!))
            let uploader = Uploader(mcp: mcp, payment: payment)
            let url = try await uploader.upload(data: png, filename: "screenshot.png", mime: "image/png")
            clipboard.copy(url)
            await NotificationService.shared.toast(title: "Copied", body: url.absoluteString)
        } catch let e as PaymentError {
            await handlePaymentError(e)
        } catch {
            await NotificationService.shared.toast(title: "Upload failed", body: "\(error)")
        }
        inFlight = false
    }

    private func handlePaymentError(_ e: PaymentError) async {
        switch e {
        case .settlementReverted, .settlementTimeout, .insufficientFunds:
            do {
                let wallet = try WalletProvider.wallet()
                let rpc = HTTPEthereumRPC(endpoint: URL(string: "https://sepolia.base.org")!)
                let usdcContract = EthereumAddress(bytes: try Data(hexString: "0x036CbD53842c5426634e7929541eC2318f3dCF7e"))
                async let usdc = wallet.balanceUSDC(contract: usdcContract, decimals: 6, rpc: rpc)
                async let eth = wallet.balanceETH(rpc: rpc)
                let (u, e2) = (try await usdc, try await eth)
                funding.present(address: wallet.address.hexString(), balanceUSDC: u, balanceETH: e2)
            } catch {
                await NotificationService.shared.toast(title: "Wallet error", body: "\(error)")
            }
        default:
            await NotificationService.shared.toast(title: "Upload failed", body: "\(e)")
        }
    }

    public func openFundingPanel() {
        Task {
            do {
                let wallet = try WalletProvider.wallet()
                let rpc = HTTPEthereumRPC(endpoint: URL(string: "https://sepolia.base.org")!)
                let usdcContract = EthereumAddress(bytes: try Data(hexString: "0x036CbD53842c5426634e7929541eC2318f3dCF7e"))
                async let usdc = wallet.balanceUSDC(contract: usdcContract, decimals: 6, rpc: rpc)
                async let eth = wallet.balanceETH(rpc: rpc)
                let (u, e) = (try await usdc, try await eth)
                funding.present(address: wallet.address.hexString(), balanceUSDC: u, balanceETH: e)
            } catch {}
        }
    }
}
