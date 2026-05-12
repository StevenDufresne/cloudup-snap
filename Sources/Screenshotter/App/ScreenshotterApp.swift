import AppKit
import ScreenshotterCore

@MainActor
@main
final class ScreenshotterApp: NSObject, NSApplicationDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = ScreenshotterApp()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)   // ensures LSUIElement behavior at runtime too
        app.run()
    }

    let menubar = MenubarController()
    let hotkey = HotkeyManager()
    let onboarding = OnboardingCoordinator()
    let coordinator = CaptureCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        menubar.onCaptureRegion = { [weak self] in self?.coordinator.startCapture(mode: .region) }
        menubar.onCaptureWindow = { [weak self] in self?.coordinator.startCapture(mode: .window) }
        menubar.onCaptureFullScreen = { [weak self] in self?.coordinator.startCapture(mode: .fullScreen) }
        menubar.onOpenFundingPanel = { [weak self] in self?.coordinator.openFundingPanel() }

        hotkey.register { [weak self] in self?.coordinator.startCapture(mode: .region) }

        if let wallet = try? WalletProvider.wallet() {
            onboarding.presentIfNeeded(walletAddress: wallet.address.hexString())
        }
    }
}
