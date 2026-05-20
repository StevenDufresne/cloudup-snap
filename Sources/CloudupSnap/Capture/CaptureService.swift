import Foundation
import ScreenCaptureKit
import CoreGraphics
import AppKit

public enum CaptureMode: Sendable {
    case region
    case window
    case fullScreen
}

public enum CaptureError: Error {
    case permissionDenied
    case noDisplays
    case captureFailed(String)
    case cancelled
}

/// Capture service backed by macOS's `/usr/sbin/screencapture` CLI. This
/// sidesteps the per-app ScreenCaptureKit TCC entitlement that's been
/// unreliable in our development setup — `screencapture` is a system tool
/// with its own stable permission story.
public actor CaptureService {
    public init() {}

    /// Capture an entire display via ScreenCaptureKit. Targets a specific
    /// `CGDirectDisplayID` so multi-monitor setups capture the right screen,
    /// unlike `screencapture` (which only does the primary without `-D`, and
    /// `-D` enumerates differently from `CGGetActiveDisplayList`).
    public func captureFullScreen(displayID: CGDirectDisplayID, pixelScale: CGFloat) async throws -> CGImage {
        let content = try await SCShareableContent.current
        guard let scDisplay = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.captureFailed("no SCDisplay for displayID \(displayID)")
        }
        let config = SCStreamConfiguration()
        config.width = max(1, Int(CGFloat(scDisplay.width) * pixelScale))
        config.height = max(1, Int(CGFloat(scDisplay.height) * pixelScale))
        let filter = SCContentFilter(display: scDisplay, excludingWindows: [])
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    /// Capture a rect on a specific display via ScreenCaptureKit. We use SCK here
    /// rather than `screencapture -D -R` because `screencapture`'s display-index
    /// enumeration doesn't match `CGGetActiveDisplayList`'s ordering on
    /// multi-monitor setups, so the `-D` flag was sending captures to the wrong
    /// monitor. SCK takes a `CGDirectDisplayID` directly.
    ///
    /// `rect` is in DISPLAY-LOCAL coordinates (top-left origin of the display).
    public func captureRegion(_ rect: CGRect, displayID: CGDirectDisplayID, pixelScale: CGFloat) async throws -> CGImage {
        let content = try await SCShareableContent.current
        guard let scDisplay = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.captureFailed("no SCDisplay for displayID \(displayID)")
        }
        let config = SCStreamConfiguration()
        config.width = max(1, Int(rect.width * pixelScale))
        config.height = max(1, Int(rect.height * pixelScale))
        config.sourceRect = rect
        let filter = SCContentFilter(display: scDisplay, excludingWindows: [])
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    /// Window capture is interactive (`screencapture -w`) — user clicks the
    /// window they want. We still take the result and feed it into the editor.
    public func captureWindowInteractive() async throws -> CGImage {
        let tmp = try tmpPath()
        try await run(args: ["-x", "-t", "png", "-w", tmp])
        return try loadImage(at: tmp)
    }

    // MARK: -

    private func tmpPath() throws -> String {
        let dir = NSTemporaryDirectory()
        return dir + "cloudupsnap-\(UUID().uuidString).png"
    }

    private func run(args: [String]) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            proc.arguments = args
            proc.terminationHandler = { p in
                if p.terminationStatus == 0 {
                    cont.resume()
                } else {
                    cont.resume(throwing: CaptureError.captureFailed("screencapture exited \(p.terminationStatus)"))
                }
            }
            do {
                try proc.run()
            } catch {
                cont.resume(throwing: error)
            }
        }
    }

    private func loadImage(at path: String) throws -> CGImage {
        guard let data = NSData(contentsOfFile: path),
              let provider = CGDataProvider(data: data),
              let img = CGImage(pngDataProviderSource: provider, decode: nil,
                                shouldInterpolate: false, intent: .defaultIntent) else {
            throw CaptureError.captureFailed("failed to read \(path)")
        }
        try? FileManager.default.removeItem(atPath: path)
        return img
    }
}
