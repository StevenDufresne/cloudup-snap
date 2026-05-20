import AppKit
import CoreGraphics
import Foundation
import CloudupSnapCore

/// File-based logger so we can read app output regardless of how the app was launched.
enum AppLog {
    static let path: String = {
        let base = NSHomeDirectory() + "/Library/Logs/CloudupSnap"
        try? FileManager.default.createDirectory(atPath: base, withIntermediateDirectories: true)
        return base + "/app.log"
    }()
    static func write(_ msg: String) {
        let line = "[\(Date())] \(msg)\n"
        if let data = line.data(using: .utf8) {
            if let fh = FileHandle(forWritingAtPath: path) {
                fh.seekToEndOfFile()
                fh.write(data)
                try? fh.close()
            } else {
                try? data.write(to: URL(fileURLWithPath: path))
            }
        }
        FileHandle.standardError.write(line.data(using: .utf8)!)
    }
}

@MainActor
@main
final class CloudupSnapApp: NSObject, NSApplicationDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = CloudupSnapApp()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)   // ensures LSUIElement behavior at runtime too
        app.run()
    }

    // Created lazily inside applicationDidFinishLaunching so they're constructed
    // AFTER setActivationPolicy(.accessory). Status items registered before
    // activation policy is set can be silently dropped on macOS 26.
    var menubar: MenubarController!
    var hotkey: HotkeyManager!
    var onboarding: OnboardingCoordinator!
    var coordinator: CaptureCoordinator!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set the app icon at runtime (Activity Monitor, About panel, Force
        // Quit dialog). The bundle's Finder icon is set separately via
        // the .icns file copied during bundle.sh.
        NSApp.applicationIconImage = CloudupIcon.appIconImage(size: 512)

        AppLog.write("=== Launched, pid=\(ProcessInfo.processInfo.processIdentifier) ===")
        AppLog.write("bundlePath=\(Bundle.main.bundlePath)")
        AppLog.write("bundleID=\(Bundle.main.bundleIdentifier ?? "nil")")
        let preflight = CGPreflightScreenCaptureAccess()
        AppLog.write("CGPreflightScreenCaptureAccess=\(preflight)")
        if !preflight {
            let req = CGRequestScreenCaptureAccess()
            AppLog.write("CGRequestScreenCaptureAccess=\(req)")
        }

        menubar = MenubarController()
        hotkey = HotkeyManager()
        onboarding = OnboardingCoordinator()
        coordinator = CaptureCoordinator()

        menubar.onCaptureRegion = { [weak self] in self?.coordinator.startCapture(mode: .region) }
        menubar.onCaptureWindow = { [weak self] in self?.coordinator.startCapture(mode: .window) }
        menubar.onCaptureFullScreen = { [weak self] in self?.coordinator.startCapture(mode: .fullScreen) }
        menubar.onRecordRegion = { [weak self] in self?.coordinator.startRecording(fullScreen: false) }
        menubar.onRecordFullScreen = { [weak self] in self?.coordinator.startRecording(fullScreen: true) }
        menubar.onOpenFundingPanel = { [weak self] in self?.coordinator.openFundingPanel() }

        hotkey.register { [weak self] in self?.coordinator.startCapture(mode: .region) }

        // Defer onboarding to next run-loop tick so the activation/animation
        // machinery has settled. Showing a window directly from
        // applicationDidFinishLaunching on an LSUIElement app crashes on
        // macOS 26.5 in _NSWindowTransformAnimation dealloc.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let wallet = try? WalletProvider.wallet() {
                self.onboarding.presentIfNeeded(walletAddress: wallet.address.hexString())
            }
        }
    }
}
