import AppKit

@MainActor
public final class MenubarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let recentSubmenu = NSMenu(title: "Recent Uploads")
    private let recentSubmenuItem = NSMenuItem(title: "Recent Uploads", action: nil, keyEquivalent: "")
    private var recentLimit = 15
    public var onCaptureRegion: (() -> Void)?
    public var onCaptureWindow: (() -> Void)?
    public var onCaptureFullScreen: (() -> Void)?
    public var onRecordRegion: (() -> Void)?
    public var onRecordFullScreen: (() -> Void)?
    public var onOpenFundingPanel: (() -> Void)?
    public var onQuit: (() -> Void)?

    public override init() {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        if let button = statusItem.button {
            // Cloudup logo, native-rendered as a template image (system tints it).
            button.image = CloudupIcon.menubarImage(size: 18)
            button.image?.accessibilityDescription = "Cloudup Snap"
            FileHandle.standardError.write("[Menubar] statusItem set up with Cloudup glyph\n".data(using: .utf8)!)
        } else {
            FileHandle.standardError.write("[Menubar] statusItem.button was nil!\n".data(using: .utf8)!)
        }
        recentSubmenu.delegate = self
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
        let recordRegion = NSMenuItem(title: "Record Region…", action: #selector(handleRecordRegion), keyEquivalent: "")
        recordRegion.target = self
        let recordFull = NSMenuItem(title: "Record Full Screen", action: #selector(handleRecordFullScreen), keyEquivalent: "")
        recordFull.target = self
        recentSubmenuItem.submenu = recentSubmenu
        let wallet = NSMenuItem(title: "Wallet…", action: #selector(openFunding), keyEquivalent: "")
        wallet.target = self
        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        for item in [region, window, full, .separator(), recordRegion, recordFull, .separator(), recentSubmenuItem, .separator(), wallet, .separator(), quit] {
            menu.addItem(item)
        }
        statusItem.menu = menu
    }

    // MARK: - NSMenuDelegate

    public func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === recentSubmenu else { return }
        menu.removeAllItems()
        Task { [weak self] in
            guard let self else { return }
            let entries = await HistoryStore.shared.recent(limit: recentLimit)
            await MainActor.run {
                self.populateRecent(entries: entries)
            }
        }
    }

    private func populateRecent(entries: [HistoryEntry]) {
        recentSubmenu.removeAllItems()
        if entries.isEmpty {
            let none = NSMenuItem(title: "No uploads yet", action: nil, keyEquivalent: "")
            none.isEnabled = false
            recentSubmenu.addItem(none)
            return
        }
        for entry in entries {
            let item = NSMenuItem(title: entry.menuLabel(),
                                  action: #selector(handleRecent(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.toolTip = entry.url
            item.representedObject = entry.url
            recentSubmenu.addItem(item)
        }
        recentSubmenu.addItem(.separator())
        let clear = NSMenuItem(title: "Clear history", action: #selector(clearHistory), keyEquivalent: "")
        clear.target = self
        recentSubmenu.addItem(clear)
    }

    @objc private func handleRecent(_ sender: NSMenuItem) {
        guard let urlString = sender.representedObject as? String,
              let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
        // Copy as a free side effect so paste-into-message still works.
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(urlString, forType: .string)
    }

    @objc private func clearHistory() {
        Task { await HistoryStore.shared.clear() }
    }

    private func log(_ msg: String) {
        FileHandle.standardError.write("[Menubar] \(msg)\n".data(using: .utf8)!)
    }

    @objc private func captureRegion() { log("captureRegion clicked"); onCaptureRegion?() }
    @objc private func captureWindow() { log("captureWindow clicked"); onCaptureWindow?() }
    @objc private func captureFullScreen() { log("captureFullScreen clicked"); onCaptureFullScreen?() }
    @objc private func handleRecordRegion() { log("recordRegion clicked"); onRecordRegion?() }
    @objc private func handleRecordFullScreen() { log("recordFullScreen clicked"); onRecordFullScreen?() }
    @objc private func openFunding() { log("openFunding clicked"); onOpenFundingPanel?() }
    @objc private func quit() { onQuit?(); NSApp.terminate(nil) }
}
