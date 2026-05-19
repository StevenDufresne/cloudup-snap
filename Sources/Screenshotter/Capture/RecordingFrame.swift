import AppKit

/// Four thin borderless windows forming a colored frame *around* the
/// recorded region. The windows sit just outside the rect, so the
/// highlight is visible to the user but doesn't end up in the recording.
@MainActor
public final class RecordingFrame {
    private var bars: [NSWindow] = []

    public init() {}

    public func present(rect: CGRect, color: NSColor = NSColor.systemRed, thickness: CGFloat = 4) {
        dismiss()
        let top = NSRect(
            x: rect.minX - thickness,
            y: rect.maxY,
            width: rect.width + thickness * 2,
            height: thickness)
        let bottom = NSRect(
            x: rect.minX - thickness,
            y: rect.minY - thickness,
            width: rect.width + thickness * 2,
            height: thickness)
        let left = NSRect(
            x: rect.minX - thickness,
            y: rect.minY,
            width: thickness,
            height: rect.height)
        let right = NSRect(
            x: rect.maxX,
            y: rect.minY,
            width: thickness,
            height: rect.height)
        bars = [top, bottom, left, right].map { makeBar(frame: $0, color: color) }
        bars.forEach { $0.orderFrontRegardless() }
    }

    public func dismiss() {
        bars.forEach { $0.orderOut(nil) }
        bars.removeAll()
    }

    private func makeBar(frame: NSRect, color: NSColor) -> NSWindow {
        let win = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        win.level = .screenSaver
        win.isOpaque = false
        win.backgroundColor = color.withAlphaComponent(0.9)
        win.hasShadow = false
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        win.isReleasedWhenClosed = false
        return win
    }
}
