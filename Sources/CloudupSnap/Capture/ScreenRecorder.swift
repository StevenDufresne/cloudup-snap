import Foundation
@preconcurrency import ScreenCaptureKit
import AVFoundation
import CoreMedia
import CoreGraphics

/// Captures display frames via SCStream and encodes them to H.264 MP4 with
/// AVAssetWriter. Single-shot: start → stop returns the output file URL.
///
/// We use AVAssetWriter (vs. SCRecordingOutput, macOS 15+) so the recorder
/// works on our macOS 14 deployment target. Frames arrive on a private GCD
/// queue; mutable state is guarded by `lock`.
public final class ScreenRecorder: NSObject, SCStreamOutput, SCStreamDelegate, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    public struct Options: Sendable {
        public let displayID: CGDirectDisplayID
        public let sourceRect: CGRect?      // display-local coords, top-left origin; nil = full display
        public let pixelScale: CGFloat
        public let frameRate: Int32          // fps cap (e.g. 30)
        public let longSidePixelCap: Int     // downsample if larger
        public let bitsPerSecond: Int        // H.264 bitrate
        public init(displayID: CGDirectDisplayID, sourceRect: CGRect?, pixelScale: CGFloat,
                    frameRate: Int32 = 30, longSidePixelCap: Int = 1920, bitsPerSecond: Int = 4_000_000) {
            self.displayID = displayID
            self.sourceRect = sourceRect
            self.pixelScale = pixelScale
            self.frameRate = frameRate
            self.longSidePixelCap = longSidePixelCap
            self.bitsPerSecond = bitsPerSecond
        }
    }

    private let lock = NSLock()
    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var audioCaptureSession: AVCaptureSession?
    private var sessionStarted = false
    private var sessionStartPTS: CMTime?
    private var outputURL: URL?
    private var isPaused = false
    private var isStopping = false
    /// PTS captured on the first frame received while paused. Used on
    /// resume to compute the gap to subtract from subsequent timestamps.
    private var pauseStartPTS: CMTime?
    /// Sum of all pause-gap durations. Subtracted from every appended
    /// frame's PTS so the resulting MP4 has a continuous timeline with
    /// no frozen-on-last-frame stretches.
    private var accumulatedPauseOffset: CMTime = .zero
    private let frameQueue = DispatchQueue(label: "ScreenRecorder.frames", qos: .userInitiated)
    private let audioQueue = DispatchQueue(label: "ScreenRecorder.audio", qos: .userInitiated)

    public override init() { super.init() }

    public func start(
        options: Options,
        outputURL: URL,
        excludingWindowIDs: [CGWindowID] = [],
        recordsMicrophone: Bool = false
    ) async throws {
        let content = try await SCShareableContent.current
        guard let display = content.displays.first(where: { $0.displayID == options.displayID }) else {
            throw CaptureError.captureFailed("no SCDisplay for displayID \(options.displayID)")
        }
        let excludedWindows: [SCWindow] = excludingWindowIDs.isEmpty
            ? []
            : content.windows.filter { excludingWindowIDs.contains($0.windowID) }
        let config = SCStreamConfiguration()
        let rawW: Int
        let rawH: Int
        if let r = options.sourceRect {
            config.sourceRect = r
            rawW = max(2, Int(r.width * options.pixelScale))
            rawH = max(2, Int(r.height * options.pixelScale))
        } else {
            rawW = max(2, Int(CGFloat(display.width) * options.pixelScale))
            rawH = max(2, Int(CGFloat(display.height) * options.pixelScale))
        }
        // Downscale if needed; force even dimensions for H.264.
        let longSide = max(rawW, rawH)
        let scale: CGFloat = longSide > options.longSidePixelCap
            ? CGFloat(options.longSidePixelCap) / CGFloat(longSide) : 1.0
        let outW = (max(2, Int(CGFloat(rawW) * scale)) / 2) * 2
        let outH = (max(2, Int(CGFloat(rawH) * scale)) / 2) * 2
        config.width = outW
        config.height = outH
        config.minimumFrameInterval = CMTime(value: 1, timescale: options.frameRate)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.queueDepth = 6
        config.showsCursor = true

        try? FileManager.default.removeItem(at: outputURL)
        let w = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: outW,
            AVVideoHeightKey: outH,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: options.bitsPerSecond,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: Int(options.frameRate) * 2,
            ],
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        guard w.canAdd(input) else {
            throw CaptureError.captureFailed("AVAssetWriter rejected video input")
        }
        w.add(input)

        let microphone = recordsMicrophone ? try await makeMicrophoneCapture(writer: w) : nil
        guard w.startWriting() else {
            throw CaptureError.captureFailed("AVAssetWriter.startWriting failed: \(w.error?.localizedDescription ?? "?")")
        }

        let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
        let s = SCStream(filter: filter, configuration: config, delegate: self)
        try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: frameQueue)
        try await s.startCapture()

        installState(
            stream: s,
            writer: w,
            videoInput: input,
            audioInput: microphone?.writerInput,
            audioCaptureSession: microphone?.captureSession,
            outputURL: outputURL)
        microphone?.captureSession.startRunning()
    }

    public func pause() {
        setPaused(true)
    }

    public func resume() {
        setPaused(false)
    }

    private func setPaused(_ paused: Bool) {
        lock.lock()
        defer { lock.unlock() }
        isPaused = paused
    }

    public func stop() async throws -> URL {
        let snapshot = takeStreamForStop()
        guard let (s, w, videoInput, audioInput, audioSession, url) = snapshot else {
            throw CaptureError.captureFailed("recorder not running")
        }
        audioSession?.stopRunning()
        try? await s.stopCapture()
        videoInput.markAsFinished()
        audioInput?.markAsFinished()
        await w.finishWriting()
        clearWriterState()
        if w.status == .failed {
            throw CaptureError.captureFailed("AVAssetWriter failed: \(w.error?.localizedDescription ?? "?")")
        }
        return url
    }

    private func makeMicrophoneCapture(writer: AVAssetWriter) async throws -> (captureSession: AVCaptureSession, writerInput: AVAssetWriterInput) {
        try await Self.ensureMicrophoneAccess()
        guard let device = AVCaptureDevice.default(for: .audio) else {
            throw CaptureError.captureFailed("No microphone is available")
        }

        let session = AVCaptureSession()
        session.beginConfiguration()
        session.sessionPreset = .high
        defer { session.commitConfiguration() }

        let deviceInput = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(deviceInput) else {
            throw CaptureError.captureFailed("AVCaptureSession rejected microphone input")
        }
        session.addInput(deviceInput)

        let output = AVCaptureAudioDataOutput()
        output.setSampleBufferDelegate(self, queue: audioQueue)
        guard session.canAddOutput(output) else {
            throw CaptureError.captureFailed("AVCaptureSession rejected microphone output")
        }
        session.addOutput(output)

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64_000,
        ]
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else {
            throw CaptureError.captureFailed("AVAssetWriter rejected microphone input")
        }
        writer.add(input)
        return (session, input)
    }

    private static func ensureMicrophoneAccess() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return
        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
            if granted { return }
            throw CaptureError.permissionDenied
        default:
            throw CaptureError.permissionDenied
        }
    }

    // Sync helpers — lock operations are forbidden directly from async
    // functions under Swift 6 strict concurrency, so we wrap each
    // critical section in its own non-async method.
    private func installState(
        stream: SCStream,
        writer: AVAssetWriter,
        videoInput: AVAssetWriterInput,
        audioInput: AVAssetWriterInput?,
        audioCaptureSession: AVCaptureSession?,
        outputURL: URL
    ) {
        lock.lock()
        defer { lock.unlock() }
        self.stream = stream
        self.writer = writer
        self.videoInput = videoInput
        self.audioInput = audioInput
        self.audioCaptureSession = audioCaptureSession
        self.outputURL = outputURL
        self.sessionStarted = false
        self.sessionStartPTS = nil
        self.isPaused = false
        self.isStopping = false
        self.pauseStartPTS = nil
        self.accumulatedPauseOffset = .zero
    }

    private func takeStreamForStop() -> (SCStream, AVAssetWriter, AVAssetWriterInput, AVAssetWriterInput?, AVCaptureSession?, URL)? {
        lock.lock()
        defer { lock.unlock() }
        guard let s = stream, let w = writer, let i = videoInput, let u = outputURL else {
            return nil
        }
        let audioSession = audioCaptureSession
        let audioWriterInput = audioInput
        self.stream = nil
        self.audioCaptureSession = nil
        self.isStopping = true
        return (s, w, i, audioWriterInput, audioSession, u)
    }

    private func clearWriterState() {
        lock.lock()
        defer { lock.unlock() }
        self.writer = nil
        self.videoInput = nil
        self.audioInput = nil
        self.outputURL = nil
        self.sessionStartPTS = nil
        self.isStopping = false
    }

    // MARK: - SCStreamOutput

    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, CMSampleBufferIsValid(sampleBuffer) else { return }
        // Only forward .complete frames; SCStream emits .idle / .blank etc. that
        // AVAssetWriter would reject or treat as a zero-content frame.
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let first = attachments.first,
              let raw = first[.status] as? Int,
              let status = SCFrameStatus(rawValue: raw),
              status == .complete else { return }

        lock.lock()
        defer { lock.unlock() }
        guard !isStopping else { return }
        guard let writer = writer, let input = videoInput else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        if isPaused {
            // Mark the start of the pause window the first time we see a frame
            // after pause() was called. On resume we use this to grow the
            // cumulative offset.
            if pauseStartPTS == nil { pauseStartPTS = pts }
            return
        }
        if let pauseStart = pauseStartPTS {
            let gap = CMTimeSubtract(pts, pauseStart)
            accumulatedPauseOffset = CMTimeAdd(accumulatedPauseOffset, gap)
            pauseStartPTS = nil
        }

        let adjustedPTS = CMTimeSubtract(pts, accumulatedPauseOffset)
        if !sessionStarted {
            writer.startSession(atSourceTime: adjustedPTS)
            sessionStarted = true
            sessionStartPTS = adjustedPTS
        }
        guard input.isReadyForMoreMediaData else { return }

        if accumulatedPauseOffset == .zero {
            // Fast path — no rewrite needed.
            input.append(sampleBuffer)
            return
        }
        var timing = CMSampleTimingInfo(
            duration: CMSampleBufferGetDuration(sampleBuffer),
            presentationTimeStamp: adjustedPTS,
            decodeTimeStamp: .invalid
        )
        var adjusted: CMSampleBuffer?
        let rewriteStatus = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleBufferOut: &adjusted
        )
        if rewriteStatus == noErr, let adjusted {
            input.append(adjusted)
        }
    }

    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard CMSampleBufferIsValid(sampleBuffer) else { return }

        lock.lock()
        defer { lock.unlock() }
        guard !isStopping else { return }
        guard sessionStarted, let input = audioInput else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        if isPaused {
            if pauseStartPTS == nil { pauseStartPTS = pts }
            return
        }
        if let pauseStart = pauseStartPTS {
            let gap = CMTimeSubtract(pts, pauseStart)
            accumulatedPauseOffset = CMTimeAdd(accumulatedPauseOffset, gap)
            pauseStartPTS = nil
        }

        guard input.isReadyForMoreMediaData else { return }

        let adjustedPTS = CMTimeSubtract(pts, accumulatedPauseOffset)
        guard let sessionStartPTS, CMTimeCompare(adjustedPTS, sessionStartPTS) >= 0 else { return }
        if accumulatedPauseOffset == .zero {
            input.append(sampleBuffer)
            return
        }

        var timing = CMSampleTimingInfo(
            duration: CMSampleBufferGetDuration(sampleBuffer),
            presentationTimeStamp: adjustedPTS,
            decodeTimeStamp: .invalid
        )
        var adjusted: CMSampleBuffer?
        let rewriteStatus = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleBufferOut: &adjusted
        )
        if rewriteStatus == noErr, let adjusted {
            input.append(adjusted)
        }
    }

    // MARK: - SCStreamDelegate

    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        FileHandle.standardError.write("[ScreenRecorder] stream stopped with error: \(error)\n".data(using: .utf8)!)
    }
}
