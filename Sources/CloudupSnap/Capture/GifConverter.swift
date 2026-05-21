import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Converts an MP4 (or any AVAsset-readable video) into an animated GIF.
/// Single-shot async API: `convert(...)` returns the destination URL or throws.
public enum GifConverter {
    public struct Options: Sendable {
        public let fps: Int
        /// Long-side pixel cap. `0` means use the source size.
        public let maxLongSide: Int
        public init(fps: Int, maxLongSide: Int) {
            self.fps = fps
            self.maxLongSide = maxLongSide
        }
    }

    public enum ConvertError: Error {
        case noVideoTrack
        case destinationCreationFailed
        case finalizeFailed
    }

    public static func convert(
        sourceURL: URL,
        range: CMTimeRange? = nil,
        options: Options
    ) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        let assetDuration = try await asset.load(.duration)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw ConvertError.noVideoTrack
        }
        _ = try await track.load(.naturalSize)
        _ = try await track.load(.preferredTransform)

        let effectiveRange: CMTimeRange
        if let r = range, r.duration > .zero {
            effectiveRange = r
        } else {
            effectiveRange = CMTimeRange(start: .zero, duration: assetDuration)
        }
        let totalSeconds = CMTimeGetSeconds(effectiveRange.duration)
        let frameInterval = 1.0 / Double(options.fps)
        let frameCount = max(1, Int(totalSeconds / frameInterval))
        let baseStart = CMTimeGetSeconds(effectiveRange.start)
        let times = (0..<frameCount).map {
            CMTime(seconds: baseStart + Double($0) * frameInterval, preferredTimescale: 600)
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        if options.maxLongSide > 0 {
            generator.maximumSize = CGSize(width: options.maxLongSide, height: options.maxLongSide)
        }

        let outURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cloudup-snap-\(UUID().uuidString).gif")
        guard let dest = CGImageDestinationCreateWithURL(
            outURL as CFURL,
            UTType.gif.identifier as CFString,
            frameCount,
            nil
        ) else {
            throw ConvertError.destinationCreationFailed
        }

        let fileProps: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
        ]
        CGImageDestinationSetProperties(dest, fileProps as CFDictionary)

        let frameProps: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFUnclampedDelayTime: frameInterval,
            ],
        ]

        for time in times {
            let cgImage = try await generator.image(at: time).image
            CGImageDestinationAddImage(dest, cgImage, frameProps as CFDictionary)
        }

        guard CGImageDestinationFinalize(dest) else {
            throw ConvertError.finalizeFailed
        }
        return outURL
    }

    /// Rough size estimate in bytes. Compressed-GIF size scales roughly with
    /// `width × height × frames`; the multiplier is an empirical ballpark.
    public static func estimateBytes(width: Int, height: Int, frameCount: Int) -> Int {
        Int(Double(width) * Double(height) * Double(frameCount) * 0.4)
    }
}
