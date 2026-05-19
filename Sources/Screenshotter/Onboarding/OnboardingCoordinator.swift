import AppKit
import SwiftUI

@MainActor
public final class OnboardingCoordinator {
    private var window: NSWindow?
    public init() {}

    public static var hasRun: Bool {
        get { UserDefaults.standard.bool(forKey: "onboarding.done") }
        set { UserDefaults.standard.set(newValue, forKey: "onboarding.done") }
    }

    public func presentIfNeeded(walletAddress: String) {
        guard !Self.hasRun else { return }
        let root = OnboardingView(walletAddress: walletAddress, onDone: { [weak self] in
            Self.hasRun = true
            self?.window?.close()
            self?.window = nil
        })
        let view = NSHostingView(rootView: root)
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 540),
                           styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.title = "Welcome to Cloudup Snap"
        win.contentView = view
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = win
    }
}

struct OnboardingView: View {
    let walletAddress: String
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Welcome to Cloudup Snap").font(.title)
            Text("Cloudup Snap needs two permissions and a small amount of testnet funds to work.")

            Divider()

            Text("1. Screen Recording").font(.headline)
            HStack {
                Text("Required to capture screen regions.")
                Button("Open System Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                }
            }

            Text("2. Accessibility").font(.headline)
            HStack {
                Text("Required for the ⌘⇧2 global hotkey.")
                Button("Open System Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
            }

            Divider()

            Text("3. Fund your wallet").font(.headline)
            Text("Each upload costs ~$0.05 in testnet USDC on Base Sepolia.")
            Text(walletAddress).font(.system(.body, design: .monospaced)).textSelection(.enabled)
            HStack {
                Link("Coinbase CDP Faucet", destination: URL(string: "https://portal.cdp.coinbase.com/products/faucet")!)
                Link("Circle USDC Faucet", destination: URL(string: "https://faucet.circle.com/")!)
            }

            Spacer()

            HStack {
                Spacer()
                Button("Get started", action: onDone).buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}
