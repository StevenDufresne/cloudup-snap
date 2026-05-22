import AppKit
import SwiftUI
import CoreImage.CIFilterBuiltins
import CloudupSnapCore

@MainActor
public final class FundingPanel: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    public override init() { super.init() }

    public func present(
        address: String,
        balanceUSDC: Decimal,
        balanceETH: Decimal,
        reason: String? = nil,
        onRetry: (() -> Void)? = nil
    ) {
        let root = FundingPanelView(
            address: address,
            balanceUSDC: balanceUSDC,
            balanceETH: balanceETH,
            reason: reason,
            onRetry: onRetry
        )
        let view = NSHostingView(rootView: root)
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 560),
                           styleMask: [.titled, .closable], backing: .buffered, defer: false)
        // NSWindow defaults to isReleasedWhenClosed=true, which conflicts with
        // ARC managing this strong reference: clicking the red close button
        // drops the OS-side retain, ARC's later release goes over-zero and
        // crashes the app with EXC_BAD_ACCESS during the next autorelease
        // pool drain. Keep ownership in ARC and nil it out on close instead.
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.title = "Wallet"
        win.contentView = view
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = win
    }

    public nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in self.window = nil }
    }
}

struct FundingPanelView: View {
    let address: String
    let balanceUSDC: Decimal
    let balanceETH: Decimal
    /// Optional explanation — set when the panel is shown because a payment failed.
    let reason: String?
    let onRetry: (() -> Void)?

    private static let coinbaseFaucet = URL(string: "https://portal.cdp.coinbase.com/products/faucet")!
    private static let circleFaucet   = URL(string: "https://faucet.circle.com/")!
    private static let alchemyFaucet  = URL(string: "https://www.alchemy.com/faucets/base-sepolia")!

    var body: some View {
        VStack(alignment: .center, spacing: 14) {
            if let reason = reason {
                // Show the specific failure reason at the top, in an attention color
                Text("Upload failed").font(.headline).foregroundColor(.primary)
                Text(reason)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                Divider().padding(.vertical, 4)
            }

            Text("Fund your wallet to upload").font(.headline)
            Text("Each upload pays ~$0.05 in USDC on Base Sepolia. The wallet also needs a tiny bit of ETH for transaction gas.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)

            if let qr = qrImage(for: address) {
                Image(nsImage: qr).resizable().interpolation(.none).frame(width: 180, height: 180)
            }

            HStack(spacing: 4) {
                Text(address).font(.system(.body, design: .monospaced)).truncationMode(.middle).lineLimit(1)
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(address, forType: .string)
                }.buttonStyle(.borderless)
            }

            HStack(spacing: 24) {
                VStack { Text("USDC").font(.caption).foregroundColor(.secondary); Text(balanceUSDC.description).font(.system(.body, design: .monospaced)) }
                VStack { Text("ETH").font(.caption).foregroundColor(.secondary);  Text(balanceETH.description).font(.system(.body, design: .monospaced)) }
            }

            // Faucet links — bring the user directly where they need to go.
            VStack(alignment: .leading, spacing: 6) {
                Text("Faucets").font(.caption).foregroundColor(.secondary)
                Link(destination: Self.coinbaseFaucet) {
                    Label("Coinbase CDP (ETH + USDC)", systemImage: "drop.fill")
                }
                Link(destination: Self.circleFaucet) {
                    Label("Circle (USDC only)", systemImage: "dollarsign.circle")
                }
                Link(destination: Self.alchemyFaucet) {
                    Label("Alchemy (ETH only)", systemImage: "fuelpump")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)

            if let onRetry = onRetry {
                Button("I've funded — retry upload", action: onRetry)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return)
            }
        }
        .padding(20)
        .frame(width: 420)
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
