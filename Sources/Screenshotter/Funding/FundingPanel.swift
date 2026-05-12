import AppKit
import SwiftUI
import CoreImage.CIFilterBuiltins
import ScreenshotterCore

@MainActor
public final class FundingPanel {
    private var window: NSWindow?
    public init() {}

    public func present(address: String, balanceUSDC: Decimal, balanceETH: Decimal, onRetry: (() -> Void)? = nil) {
        let root = FundingPanelView(address: address, balanceUSDC: balanceUSDC, balanceETH: balanceETH, onRetry: onRetry)
        let view = NSHostingView(rootView: root)
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 460),
                           styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.title = "Wallet"
        win.contentView = view
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = win
    }
}

struct FundingPanelView: View {
    let address: String
    let balanceUSDC: Decimal
    let balanceETH: Decimal
    let onRetry: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Text("Fund your wallet on Base Sepolia").font(.headline)
            if let qr = qrImage(for: address) {
                Image(nsImage: qr).resizable().interpolation(.none).frame(width: 200, height: 200)
            }
            HStack(spacing: 4) {
                Text(address).font(.system(.body, design: .monospaced)).truncationMode(.middle).lineLimit(1)
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(address, forType: .string)
                }.buttonStyle(.borderless)
            }
            HStack(spacing: 16) {
                VStack { Text("USDC").font(.caption); Text(balanceUSDC.description).font(.system(.body, design: .monospaced)) }
                VStack { Text("ETH").font(.caption); Text(balanceETH.description).font(.system(.body, design: .monospaced)) }
            }
            Text("Fund with Base Sepolia ETH (for gas) + USDC (for upload fees).")
                .font(.footnote).multilineTextAlignment(.center).foregroundColor(.secondary)
            if let onRetry = onRetry {
                Button("I've funded — retry upload", action: onRetry).buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func qrImage(for text: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        guard let ci = filter.outputImage else { return nil }
        let scaled = ci.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let rep = NSCIImageRep(ciImage: scaled)
        let img = NSImage(size: rep.size)
        img.addRepresentation(rep)
        return img
    }
}
