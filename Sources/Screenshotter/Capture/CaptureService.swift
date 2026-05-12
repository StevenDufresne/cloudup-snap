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
    case captureFailed
    case cancelled
}

public actor CaptureService {
    public init() {}

    public func captureFullScreen() async throws -> CGImage {
        let content = try await SCShareableContent.current
        guard let display = content.displays.first else { throw CaptureError.noDisplays }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        let scale = await MainActor.run { NSScreen.main?.backingScaleFactor ?? 2.0 }
        config.width = Int(CGFloat(display.width) * scale)
        config.height = Int(CGFloat(display.height) * scale)
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    public func captureWindow(_ window: SCWindow) async throws -> CGImage {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        let scale = await MainActor.run { NSScreen.main?.backingScaleFactor ?? 2.0 }
        config.width = Int(window.frame.width * scale)
        config.height = Int(window.frame.height * scale)
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    public func shareableContent() async throws -> SCShareableContent {
        try await SCShareableContent.current
    }

    /// Convenience: crop a captured CGImage to the user-selected region.
    /// Caller is responsible for accounting for backing scale.
    public nonisolated func crop(_ image: CGImage, to rect: CGRect) -> CGImage? {
        image.cropping(to: rect)
    }
}
