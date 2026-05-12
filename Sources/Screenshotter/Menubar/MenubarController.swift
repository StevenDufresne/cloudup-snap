import AppKit

@MainActor
public final class MenubarController {
    private let statusItem: NSStatusItem
    public var onCaptureRegion: (() -> Void)?
    public var onCaptureWindow: (() -> Void)?
    public var onCaptureFullScreen: (() -> Void)?
    public var onOpenFundingPanel: (() -> Void)?
    public var onQuit: (() -> Void)?

    public init() {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "scissors", accessibilityDescription: "Screenshotter")
        }
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let region = NSMenuItem(title: "Capture Region (⌘⇧2)", action: #selector(captureRegion), keyEquivalent: "")
        region.target = self
        let window = NSMenuItem(title: "Capture Window…", action: #selector(captureWindow), keyEquivalent: "")
        window.target = self
        let full = NSMenuItem(title: "Capture Full Screen", action: #selector(captureFullScreen), keyEquivalent: "")
        full.target = self
        let wallet = NSMenuItem(title: "Wallet…", action: #selector(openFunding), keyEquivalent: "")
        wallet.target = self
        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        for item in [region, window, full, .separator(), wallet, .separator(), quit] {
            menu.addItem(item)
        }
        statusItem.menu = menu
    }

    @objc private func captureRegion() { onCaptureRegion?() }
    @objc private func captureWindow() { onCaptureWindow?() }
    @objc private func captureFullScreen() { onCaptureFullScreen?() }
    @objc private func openFunding() { onOpenFundingPanel?() }
    @objc private func quit() { onQuit?(); NSApp.terminate(nil) }
}
