import AppKit
import Foundation

@MainActor
public final class RegionSelectionOverlay {
    private var window: NSWindow?
    private var completion: ((CGRect?) -> Void)?

    public init() {}

    public func present(completion: @escaping (CGRect?) -> Void) {
        self.completion = completion
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let win = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        win.isOpaque = false
        win.backgroundColor = .clear
        win.level = .screenSaver
        win.ignoresMouseEvents = false
        win.hasShadow = false
        let view = SelectionView(frame: screen.frame) { [weak self] rect in
            self?.finish(rect)
        }
        win.contentView = view
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = win
    }

    private func finish(_ rect: CGRect?) {
        window?.orderOut(nil)
        window = nil
        let cb = completion
        completion = nil
        cb?(rect)
    }
}

private final class SelectionView: NSView {
    private var startPoint: NSPoint?
    private var currentRect: NSRect = .zero
    private let onComplete: (CGRect?) -> Void

    init(frame: NSRect, onComplete: @escaping (CGRect?) -> Void) {
        self.onComplete = onComplete
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {   // Esc
            onComplete(nil)
        }
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentRect = .zero
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let s = startPoint else { return }
        let p = convert(event.locationInWindow, from: nil)
        currentRect = NSRect(x: min(s.x, p.x), y: min(s.y, p.y),
                             width: abs(p.x - s.x), height: abs(p.y - s.y))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard currentRect.width > 4, currentRect.height > 4, let screen = window?.screen else {
            onComplete(nil); return
        }
        let global = NSRect(
            x: screen.frame.origin.x + currentRect.origin.x,
            y: screen.frame.origin.y + currentRect.origin.y,
            width: currentRect.width, height: currentRect.height
        )
        onComplete(global)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0, alpha: 0.35).setFill()
        bounds.fill()
        if currentRect != .zero {
            NSColor.clear.setFill()
            NSBezierPath(rect: currentRect).fill()
            NSColor.systemBlue.setStroke()
            let path = NSBezierPath(rect: currentRect)
            path.lineWidth = 2
            path.stroke()
        }
    }
}
