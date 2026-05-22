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
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 640),
                           styleMask: [.titled, .closable], backing: .buffered, defer: false)
        // NSWindow's isReleasedWhenClosed defaults to true; combined with the
        // strong `self.window` reference that creates a double-release on
        // close (crashes on the next autorelease-pool drain). Let ARC own it.
        win.isReleasedWhenClosed = false
        win.title = "Welcome to Cloudup Snap"
        win.contentView = view
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = win
    }
}

struct OnboardingView: View {
    @State private var address: String
    @State private var importInput: String = ""
    @State private var importStatus: ImportStatus = .idle
    let onDone: () -> Void

    init(walletAddress: String, onDone: @escaping () -> Void) {
        _address = State(initialValue: walletAddress)
        self.onDone = onDone
    }

    enum ImportStatus: Equatable {
        case idle
        case success
        case failure(String)
    }

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
            Text(address).font(.system(.body, design: .monospaced)).textSelection(.enabled)
            HStack {
                Link("Coinbase CDP Faucet", destination: URL(string: "https://portal.cdp.coinbase.com/products/faucet")!)
                Link("Circle USDC Faucet", destination: URL(string: "https://faucet.circle.com/")!)
            }

            DisclosureGroup("Already have a wallet? Import a private key") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Paste a 32-byte hex private key (with or without `0x`). It replaces the auto-generated wallet in your Keychain.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        SecureField("0x…", text: $importInput)
                            .textFieldStyle(.roundedBorder)
                        Button("Import") { attemptImport() }
                            .disabled(importInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    switch importStatus {
                    case .idle:
                        EmptyView()
                    case .success:
                        Text("Imported. Wallet address updated.")
                            .font(.caption).foregroundStyle(.green)
                    case .failure(let msg):
                        Text(msg).font(.caption).foregroundStyle(.red)
                    }
                }
                .padding(.top, 4)
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

    private func attemptImport() {
        let confirm = NSAlert()
        confirm.messageText = "Replace current wallet?"
        confirm.informativeText = "This overwrites the wallet stored in your Keychain. Any funds in the current wallet will become inaccessible from this app."
        confirm.alertStyle = .warning
        confirm.addButton(withTitle: "Replace")
        confirm.addButton(withTitle: "Cancel")
        guard confirm.runModal() == .alertFirstButtonReturn else { return }

        do {
            let wallet = try WalletProvider.importPrivateKey(hex: importInput)
            address = wallet.address.hexString()
            importInput = ""
            if WalletProvider.keyFileExists {
                importStatus = .failure(
                    "Saved to Keychain, but \(WalletProvider.keyFilePath) still exists and overrides it. Delete that file to use the imported key."
                )
            } else {
                importStatus = .success
            }
        } catch {
            importStatus = .failure("Couldn't import key: \(error)")
        }
    }
}
