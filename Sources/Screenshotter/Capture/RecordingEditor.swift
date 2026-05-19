import AppKit
import AVKit
@preconcurrency import AVFoundation
import Foundation

/// Preview window shown after a recording stops. Lets the user watch the clip
/// back before deciding to upload or cancel. Mirrors `AnnotationEditor`:
/// `present(fileURL:completion:)` returns the same URL to the completion on
/// Upload, or nil on Cancel / window close.
@MainActor
public final class RecordingEditor: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var player: AVPlayer?
    private var playerView: AVPlayerView?
    private var statusLabel: NSTextField?
    private var uploadButton: NSButton?
    private var cancelButton: NSButton?
    private var trimButton: NSButton?
    private var progress: NSProgressIndicator?
    private var completion: ((URL?) -> Void)?
    private var fileURL: URL?
    /// Set when the user committed a trim via Apple's trim UI. Applied at
    /// upload time by exporting the source asset across this range.
    private var trimRange: CMTimeRange?

    public override init() { super.init() }

    public nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in self.handleCancel() }
    }

    public func present(fileURL: URL, completion: @escaping (URL?) -> Void) {
        self.fileURL = fileURL
        self.completion = completion

        // Initial window: pick a sensible 16:9 size capped to the screen. The
        // user can resize freely; AVPlayerView fills the player area.
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let targetW = min(screen.visibleFrame.width * 0.7, 960)
        let videoH = targetW * 9.0 / 16.0
        let toolbar: CGFloat = 56
        let initialW = targetW
        let initialH = videoH + toolbar

        let container = NSView(frame: NSRect(x: 0, y: 0, width: initialW, height: initialH))
        container.autoresizingMask = [.width, .height]

        // Player on top, autoresizes with window.
        let pv = AVPlayerView(frame: NSRect(x: 0, y: toolbar, width: initialW, height: videoH))
        pv.autoresizingMask = [.width, .height, .minYMargin]
        pv.controlsStyle = .inline
        pv.showsFullScreenToggleButton = false
        container.addSubview(pv)
        self.playerView = pv

        // Toolbar bar at the bottom.
        let bar = NSView(frame: NSRect(x: 0, y: 0, width: initialW, height: toolbar))
        bar.autoresizingMask = [.width, .maxYMargin]
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        container.addSubview(bar)

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped))
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\u{1b}"  // Esc
        cancel.frame = NSRect(x: 16, y: 12, width: 88, height: 32)
        bar.addSubview(cancel)
        self.cancelButton = cancel

        let trim = NSButton(title: "Trim…", target: self, action: #selector(trimTapped))
        trim.bezelStyle = .rounded
        trim.frame = NSRect(x: 112, y: 12, width: 72, height: 32)
        bar.addSubview(trim)
        self.trimButton = trim

        // Size / status label sits between Trim and Upload.
        let bytes = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let mb = Double(bytes) / (1024 * 1024)
        let label = NSTextField(labelWithString: String(format: "%.1f MB", mb))
        label.frame = NSRect(x: 192, y: 18, width: initialW - 316, height: 20)
        label.autoresizingMask = [.width]
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        bar.addSubview(label)
        self.statusLabel = label

        let spinner = NSProgressIndicator(frame: NSRect(x: initialW - 220, y: 16, width: 24, height: 24))
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isHidden = true
        spinner.autoresizingMask = [.minXMargin]
        bar.addSubview(spinner)
        self.progress = spinner

        let upload = NSButton(title: "Upload", target: self, action: #selector(uploadTapped))
        upload.bezelStyle = .rounded
        upload.keyEquivalent = "\r"
        upload.frame = NSRect(x: initialW - 112, y: 12, width: 96, height: 32)
        upload.autoresizingMask = [.minXMargin]
        bar.addSubview(upload)
        self.uploadButton = upload

        let win = NSWindow(
            contentRect: NSRect(origin: .zero, size: CGSize(width: initialW, height: initialH)),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false
        )
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.title = "Review Recording"
        win.contentView = container
        win.contentMinSize = CGSize(width: 480, height: 320)
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = win

        let asset = AVURLAsset(url: fileURL)
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        pv.player = player
        self.player = player
        player.play()
    }

    /// Coordinator calls this to advertise progress (e.g. "Uploading…") while
    /// the window stays up. Buttons disable for the duration.
    public func setStatus(_ message: String, busy: Bool) {
        statusLabel?.stringValue = message
        uploadButton?.isEnabled = !busy
        cancelButton?.isEnabled = !busy
        trimButton?.isEnabled = !busy
        progress?.isHidden = !busy
        if busy { progress?.startAnimation(nil) } else { progress?.stopAnimation(nil) }
    }

    public func dismiss() {
        player?.pause()
        playerView?.player = nil
        player = nil
        window?.orderOut(nil)
        window = nil
        completion = nil
        fileURL = nil
    }

    @objc private func uploadTapped() {
        guard let url = fileURL else { return }
        player?.pause()
        // If the user committed a trim, export the trimmed range before
        // handing the file off to the uploader. Passthrough preset avoids
        // re-encoding when the keyframe layout allows it.
        if let range = trimRange, range.duration > .zero {
            setStatus("Trimming…", busy: true)
            Task { @MainActor in
                do {
                    let trimmed = try await self.exportTrimmed(from: url, range: range)
                    // The untrimmed source is no longer needed.
                    try? FileManager.default.removeItem(at: url)
                    self.fileURL = trimmed
                    self.setStatus("Uploading…", busy: true)
                    self.completion?(trimmed)
                } catch {
                    self.setStatus("Trim failed — \(error.localizedDescription)", busy: false)
                }
            }
            return
        }
        setStatus("Uploading…", busy: true)
        completion?(url)
    }

    @objc private func trimTapped() {
        guard let pv = playerView else { return }
        if !pv.canBeginTrimming {
            setStatus("Trim isn't available for this clip yet.", busy: false)
            return
        }
        pv.beginTrimming { [weak self] result in
            guard let self else { return }
            guard result == .okButton, let item = self.player?.currentItem else { return }
            // The trim UI moves the item's playback bounds to the new range.
            let start = item.reversePlaybackEndTime
            let end = item.forwardPlaybackEndTime
            guard start.isValid, end.isValid, CMTimeCompare(end, start) > 0 else { return }
            self.trimRange = CMTimeRange(start: start, end: end)
            let dur = CMTimeGetSeconds(CMTimeSubtract(end, start))
            self.statusLabel?.stringValue = String(format: "Trimmed to %.1fs", dur)
        }
    }

    private func exportTrimmed(from sourceURL: URL, range: CMTimeRange) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw NSError(domain: "RecordingEditor", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Couldn't create export session"])
        }
        let outURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cloudup-snap-trim-\(UUID().uuidString).mp4")
        exporter.outputURL = outURL
        exporter.outputFileType = .mp4
        exporter.timeRange = range
        return try await withCheckedThrowingContinuation { cont in
            exporter.exportAsynchronously {
                switch exporter.status {
                case .completed:
                    cont.resume(returning: outURL)
                case .failed, .cancelled:
                    cont.resume(throwing: exporter.error
                        ?? NSError(domain: "RecordingEditor", code: 2,
                                   userInfo: [NSLocalizedDescriptionKey: "Export \(exporter.status == .cancelled ? "cancelled" : "failed")"]))
                default:
                    cont.resume(throwing: NSError(domain: "RecordingEditor", code: 3,
                                                  userInfo: [NSLocalizedDescriptionKey: "Export ended in unexpected state"]))
                }
            }
        }
    }

    @objc private func cancelTapped() {
        handleCancel()
    }

    private func handleCancel() {
        let cb = completion
        let url = fileURL
        completion = nil
        fileURL = nil
        dismiss()
        if let url { try? FileManager.default.removeItem(at: url) }
        cb?(nil)
    }
}
