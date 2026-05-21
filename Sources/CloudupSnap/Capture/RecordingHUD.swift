import AppKit
import CoreGraphics

/// Always-on-top control panel for a recording session. The recording goes
/// through three states the HUD lays out differently:
///
///   ready    →  [● Record]  [Cancel]              (recorder not running)
///   recording→  [⏸ Pause]   [⏹ Stop]  + pulsing red dot, running timer
///   paused   →  [▶︎ Resume]  [⏹ Stop]  + steady amber dot, frozen timer
///
/// All transitions are user-driven via the callbacks supplied to `present`.
@MainActor
public final class RecordingHUD {
    public enum State { case ready, recording, paused }

    public struct Callbacks {
        public let onRecord: () -> Void
        public let onPause: () -> Void
        public let onResume: () -> Void
        public let onStop: () -> Void
        public let onCancel: () -> Void
        public init(onRecord: @escaping () -> Void,
                    onPause: @escaping () -> Void,
                    onResume: @escaping () -> Void,
                    onStop: @escaping () -> Void,
                    onCancel: @escaping () -> Void) {
            self.onRecord = onRecord
            self.onPause = onPause
            self.onResume = onResume
            self.onStop = onStop
            self.onCancel = onCancel
        }
    }

    private var panel: NSPanel?
    private var timer: Timer?
    private var dot: NSView?
    private var timeLabel: NSTextField?
    private var primaryButton: NSButton?      // Record / Pause / Resume
    private var secondaryButton: NSButton?    // Cancel / Stop / Stop
    private var startedAt: Date?
    private var accumulatedElapsed: TimeInterval = 0
    private var callbacks: Callbacks?
    private var state: State = .ready

    public init() {}

    /// CGWindowID of the HUD panel once presented. Used by ScreenRecorder
    /// to exclude the HUD from the captured pixels via SCContentFilter.
    public var windowID: CGWindowID? {
        panel.map { CGWindowID($0.windowNumber) }
    }

    public func present(callbacks: Callbacks) {
        self.callbacks = callbacks
        self.startedAt = nil
        self.accumulatedElapsed = 0

        let size = NSSize(width: 230, height: 44)
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let origin = NSPoint(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height - 18
        )
        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isReleasedWhenClosed = false

        let blur = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 10
        blur.layer?.masksToBounds = true
        panel.contentView = blur

        let dot = NSView(frame: NSRect(x: 14, y: 18, width: 9, height: 9))
        dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor.systemRed.cgColor
        dot.layer?.cornerRadius = 4.5
        dot.isHidden = true
        blur.addSubview(dot)
        self.dot = dot

        let time = NSTextField(labelWithString: "00:00")
        time.font = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        time.textColor = .labelColor
        time.frame = NSRect(x: 30, y: 12, width: 56, height: 20)
        time.isHidden = true
        blur.addSubview(time)
        self.timeLabel = time

        let primary = NSButton(title: "Record", target: self, action: #selector(primaryTapped))
        primary.bezelStyle = .rounded
        primary.controlSize = .small
        primary.frame = NSRect(x: 92, y: 11, width: 72, height: 22)
        blur.addSubview(primary)
        self.primaryButton = primary

        let secondary = NSButton(title: "Cancel", target: self, action: #selector(secondaryTapped))
        secondary.bezelStyle = .rounded
        secondary.controlSize = .small
        secondary.keyEquivalent = "\r"
        secondary.frame = NSRect(x: 168, y: 11, width: 52, height: 22)
        blur.addSubview(secondary)
        self.secondaryButton = secondary

        panel.orderFrontRegardless()
        self.panel = panel
        applyState(.ready)
    }

    public func setState(_ state: State) {
        applyState(state)
    }

    private func applyState(_ state: State) {
        self.state = state
        switch state {
        case .ready:
            primaryButton?.title = "Record"
            secondaryButton?.title = "Cancel"
            dot?.isHidden = true
            timeLabel?.isHidden = true
            stopPulse()
            timer?.invalidate(); timer = nil
        case .recording:
            primaryButton?.title = "Pause"
            secondaryButton?.title = "Stop"
            dot?.isHidden = false
            timeLabel?.isHidden = false
            dot?.layer?.backgroundColor = NSColor.systemRed.cgColor
            startPulse()
            if startedAt == nil { startedAt = Date() }
            ensureTimer()
        case .paused:
            primaryButton?.title = "Resume"
            secondaryButton?.title = "Stop"
            dot?.isHidden = false
            timeLabel?.isHidden = false
            dot?.layer?.backgroundColor = NSColor.systemOrange.cgColor
            stopPulse()
            // Freeze the elapsed total so the timer stops climbing while paused.
            if let started = startedAt {
                accumulatedElapsed += Date().timeIntervalSince(started)
                startedAt = nil
            }
            timer?.invalidate(); timer = nil
            tick()
        }
    }

    public func dismiss() {
        timer?.invalidate(); timer = nil
        stopPulse()
        panel?.orderOut(nil)
        panel = nil
        callbacks = nil
    }

    @objc private func primaryTapped() {
        guard let cb = callbacks else { return }
        switch state {
        case .ready:     cb.onRecord()
        case .recording: cb.onPause()
        case .paused:    cb.onResume()
        }
    }

    @objc private func secondaryTapped() {
        guard let cb = callbacks else { return }
        switch state {
        case .ready:                cb.onCancel()
        case .recording, .paused:   cb.onStop()
        }
    }

    private func startPulse() {
        guard let layer = dot?.layer else { return }
        if layer.animation(forKey: "pulse") != nil { return }
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.3
        pulse.duration = 0.8
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        layer.add(pulse, forKey: "pulse")
    }

    private func stopPulse() {
        dot?.layer?.removeAnimation(forKey: "pulse")
    }

    private func ensureTimer() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        var elapsed = accumulatedElapsed
        if let started = startedAt {
            elapsed += Date().timeIntervalSince(started)
        }
        let i = Int(elapsed)
        let mm = i / 60
        let ss = i % 60
        timeLabel?.stringValue = String(format: "%02d:%02d", mm, ss)
    }
}
