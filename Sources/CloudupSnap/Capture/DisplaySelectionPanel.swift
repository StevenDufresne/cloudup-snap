import AppKit
import CoreGraphics

@MainActor
public final class DisplaySelectionPanel: NSObject {
    private var panel: NSPanel?
    private var pickerView: DisplayPickerView?
    private var continueButton: NSButton?
    private var completion: ((NSScreen?) -> Void)?
    private var selectedScreen: NSScreen?

    public override init() {
        super.init()
    }

    public func present(completion: @escaping (NSScreen?) -> Void) {
        self.completion = completion
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            completion(nil)
            return
        }

        selectedScreen = screens.count == 1 ? screens[0] : nil

        let size = NSSize(width: 540, height: 380)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Choose Screen to Record"
        panel.isReleasedWhenClosed = false
        panel.center()

        let content = NSView(frame: NSRect(origin: .zero, size: size))
        panel.contentView = content

        let title = NSTextField(labelWithString: "Choose Screen to Record")
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        title.frame = NSRect(x: 24, y: 324, width: 492, height: 26)
        content.addSubview(title)

        let subtitle = NSTextField(labelWithString: "Select the display Cloudup Snap should record. You can still start or cancel from the recording controls next.")
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabelColor
        subtitle.frame = NSRect(x: 24, y: 294, width: 492, height: 36)
        subtitle.lineBreakMode = .byWordWrapping
        subtitle.maximumNumberOfLines = 2
        content.addSubview(subtitle)

        let picker = DisplayPickerView(
            frame: NSRect(x: 24, y: 76, width: 492, height: 200),
            screens: screens,
            initialSelection: selectedScreen
        ) { [weak self] screen in
            self?.selectedScreen = screen
            self?.continueButton?.isEnabled = true
        }
        content.addSubview(picker)
        self.pickerView = picker

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped))
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\u{1b}"
        cancel.frame = NSRect(x: 324, y: 24, width: 88, height: 32)
        content.addSubview(cancel)

        let proceed = NSButton(title: "Continue", target: self, action: #selector(continueTapped))
        proceed.bezelStyle = .rounded
        proceed.keyEquivalent = "\r"
        proceed.isEnabled = selectedScreen != nil
        proceed.frame = NSRect(x: 424, y: 24, width: 92, height: 32)
        content.addSubview(proceed)
        self.continueButton = proceed

        panel.delegate = self
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.panel = panel
    }

    @objc private func cancelTapped() {
        finish(nil)
    }

    @objc private func continueTapped() {
        finish(selectedScreen)
    }

    private func finish(_ screen: NSScreen?) {
        panel?.orderOut(nil)
        panel = nil
        pickerView = nil
        continueButton = nil
        selectedScreen = nil
        let cb = completion
        completion = nil
        cb?(screen)
    }
}

extension DisplaySelectionPanel: NSWindowDelegate {
    public func windowWillClose(_ notification: Notification) {
        finish(nil)
    }
}

private struct DisplayPickerItem {
    let screen: NSScreen
    let displayID: CGDirectDisplayID?
    let name: String
    let resolution: String
    let isMain: Bool
    let rect: NSRect
}

private final class DisplayPickerView: NSView {
    private var items: [DisplayPickerItem]
    private var selectedDisplayID: CGDirectDisplayID?
    private let onSelect: (NSScreen) -> Void

    init(frame: NSRect, screens: [NSScreen], initialSelection: NSScreen?, onSelect: @escaping (NSScreen) -> Void) {
        self.onSelect = onSelect
        self.selectedDisplayID = Self.displayID(for: initialSelection)
        self.items = Self.makeItems(screens: screens, in: frame.size)
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.cornerRadius = 8
        setAccessibilityRole(.group)
        setAccessibilityLabel("Available screens")
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let item = items.first(where: { $0.rect.contains(point) }) else { return }
        selectedDisplayID = item.displayID
        needsDisplay = true
        onSelect(item.screen)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        bounds.fill()

        for item in items {
            let selected = item.displayID == selectedDisplayID
            let bg = selected ? NSColor.controlAccentColor.withAlphaComponent(0.18) : NSColor.windowBackgroundColor
            bg.setFill()

            let path = NSBezierPath(roundedRect: item.rect, xRadius: 8, yRadius: 8)
            path.fill()

            (selected ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
            path.lineWidth = selected ? 3 : 1
            path.stroke()

            draw(item.name, in: item.rect.insetBy(dx: 12, dy: 12), font: .systemFont(ofSize: 14, weight: .semibold), color: .labelColor)
            let detail = item.isMain ? "\(item.resolution) - Main" : item.resolution
            draw(detail, in: item.rect.insetBy(dx: 12, dy: item.rect.height - 48), font: .systemFont(ofSize: 12), color: .secondaryLabelColor)
        }
    }

    private func draw(_ text: String, in rect: NSRect, font: NSFont, color: NSColor) {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: style,
        ]
        text.draw(in: rect, withAttributes: attrs)
    }

    private static func makeItems(screens: [NSScreen], in size: NSSize) -> [DisplayPickerItem] {
        let union = screens.reduce(NSRect.null) { $0.union($1.frame) }
        let padding: CGFloat = 20
        let available = NSSize(width: max(1, size.width - padding * 2), height: max(1, size.height - padding * 2))
        let scale = min(available.width / max(1, union.width), available.height / max(1, union.height))
        let drawnSize = NSSize(width: union.width * scale, height: union.height * scale)
        let offset = NSPoint(
            x: padding + (available.width - drawnSize.width) / 2,
            y: padding + (available.height - drawnSize.height) / 2
        )

        return screens.enumerated().map { index, screen in
            let frame = screen.frame
            let rect = NSRect(
                x: offset.x + (frame.minX - union.minX) * scale,
                y: offset.y + (frame.minY - union.minY) * scale,
                width: max(96, frame.width * scale),
                height: max(64, frame.height * scale)
            )
            let displayID = displayID(for: screen)
            let name = screen.localizedName.isEmpty ? "Display \(index + 1)" : screen.localizedName
            let resolution = "\(Int(frame.width * screen.backingScaleFactor)) x \(Int(frame.height * screen.backingScaleFactor))"
            return DisplayPickerItem(
                screen: screen,
                displayID: displayID,
                name: name,
                resolution: resolution,
                isMain: screen == NSScreen.main,
                rect: rect
            )
        }
    }

    private static func displayID(for screen: NSScreen?) -> CGDirectDisplayID? {
        screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
