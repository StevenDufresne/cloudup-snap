import AppKit
import Foundation
import CloudupSnapCore
@preconcurrency import ScreenCaptureKit
import CoreGraphics

@MainActor
public final class CaptureCoordinator {
    private let capture = CaptureService()
    private let regionOverlay = RegionSelectionOverlay()
    private let editor = AnnotationEditor()
    private let clipboard = ClipboardService()
    private let funding = FundingPanel()
    private let recordingHUD = RecordingHUD()
    private let recordingEditor = RecordingEditor()
    private let recordingFrame = RecordingFrame()
    private let displaySelectionPanel = DisplaySelectionPanel()
    private var recorder: ScreenRecorder?
    private let recordingMicrophoneDefaultsKey = "recording.microphone.enabled"
    /// Pending options + output for a recording that's been set up (HUD shown,
    /// frame drawn) but not yet started. Cleared once `recorder.start()` runs.
    private var pendingRecordingOptions: ScreenRecorder.Options?
    private var pendingRecordingOutputURL: URL?
    private var pendingRecordingUsesMicrophone = false
    private var recordingMaxDurationTask: Task<Void, Never>?
    private var inFlight = false

    /// Hard cap on a single recording. The HUD allows manual stop earlier,
    /// but if the user wanders off we don't want a 4 GB MP4 sitting on disk.
    private let maxRecordingSeconds: TimeInterval = 60

    public init() {}

    public func startCapture(mode: CaptureMode) {
        log("startCapture mode=\(mode) inFlight=\(inFlight)")
        if inFlight {
            // Self-heal: a previous capture got stuck (editor never closed,
            // process hung, etc.). Force-reset state so the user can try again
            // instead of silently dropping clicks forever.
            log("forcing reset of stuck inFlight state")
            editor.dismiss()
            inFlight = false
        }
        inFlight = true
        switch mode {
        case .region:
            log("presenting region overlay")
            regionOverlay.present { [weak self] selectedRect in
                guard let self else { return }
                log("region overlay returned rect=\(String(describing: selectedRect))")
                guard let rect = selectedRect else { self.inFlight = false; return }
                Task { await self.captureRegionAndEdit(rect: rect) }
            }
        case .fullScreen:
            Task { await self.captureFullAndEdit() }
        case .window:
            Task { await self.captureWindowAndEdit() }
        }
    }

    nonisolated func log(_ msg: String) {
        let line = "[\(Date())] [Coord] \(msg)\n"
        FileHandle.standardError.write(line.data(using: .utf8)!)
        let path = NSHomeDirectory() + "/Library/Logs/CloudupSnap/app.log"
        if let fh = FileHandle(forWritingAtPath: path) {
            fh.seekToEndOfFile()
            if let data = line.data(using: .utf8) { fh.write(data) }
            try? fh.close()
        }
    }

    /// 1-based screencapture `-D` index for the given NSScreen. We match by the
    /// screen's CGDirectDisplayID against the active display list.
    private func displayIndex(for screen: NSScreen) -> Int {
        guard let cgID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return 1
        }
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        if let i = ids.firstIndex(of: cgID) {
            return i + 1
        }
        return 1
    }

    private func captureRegionAndEdit(rect: CGRect) async {
        do {
            // Find the NSScreen the rect is on, derive its CGDirectDisplayID,
            // convert the rect to display-local top-left coords, and let SCK
            // capture exactly that.
            guard let screen = NSScreen.screens.first(where: { NSIntersectsRect($0.frame, rect) })
                ?? NSScreen.main else {
                inFlight = false; return
            }
            guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
                log("no CGDirectDisplayID for screen \(screen)")
                inFlight = false; return
            }
            let localX = rect.origin.x - screen.frame.origin.x
            let localY = screen.frame.maxY - rect.maxY
            let local = CGRect(x: localX, y: localY, width: rect.width, height: rect.height)
            log("region rect=\(rect) screen=\(screen.frame) local=\(local) displayID=\(displayID)")
            let img = try await capture.captureRegion(local, displayID: displayID, pixelScale: screen.backingScaleFactor)
            openEditor(with: img, sourceScale: screen.backingScaleFactor)
        } catch {
            log("capture error: \(error)")
            await NotificationService.shared.toast(title: "Capture failed", body: "\(error)")
            inFlight = false
        }
    }

    private func captureFullAndEdit() async {
        do {
            // Pick the screen the mouse is currently on so full-screen captures
            // the display the user is actually looking at, not always the main.
            let mouseLocation = NSEvent.mouseLocation
            let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
                ?? NSScreen.main
                ?? NSScreen.screens[0]
            guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
                log("captureFullAndEdit: no displayID for screen \(screen)")
                inFlight = false; return
            }
            log("captureFullAndEdit: capturing display \(displayID) (screen frame \(screen.frame))")
            let full = try await capture.captureFullScreen(displayID: displayID, pixelScale: screen.backingScaleFactor)
            log("captureFullAndEdit: got image \(full.width)x\(full.height)")
            openEditor(with: full, sourceScale: screen.backingScaleFactor)
        } catch {
            log("capture error: \(error)")
            await NotificationService.shared.toast(title: "Capture failed", body: "\(error)")
            inFlight = false
        }
    }

    private func captureWindowAndEdit() async {
        do {
            let img = try await capture.captureWindowInteractive()
            // Window capture is interactive; the user could click a window on any
            // screen. Use the screen the mouse is currently on as the best guess.
            let mouseLocation = NSEvent.mouseLocation
            let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
                ?? NSScreen.main
            let scale = screen?.backingScaleFactor ?? 2.0
            openEditor(with: img, sourceScale: scale)
        } catch {
            log("capture error: \(error)")
            await NotificationService.shared.toast(title: "Capture failed", body: "\(error)")
            inFlight = false
        }
    }

    private func openEditor(with background: CGImage, sourceScale: CGFloat) {
        log("openEditor: presenting editor (pixelScale=\(sourceScale))")
        editor.present(background: background, pixelScale: sourceScale) { [weak self] doc in
            guard let self else { return }
            if doc == nil {
                self.log("editor completion: cancelled")
                self.inFlight = false
                return
            }
            self.log("editor completion: upload requested")
            Task { await self.flattenAndUpload(doc: doc!) }
        }
    }

    private func flattenAndUpload(doc: AnnotationDocument) async {
        log("flattenAndUpload: start")
        defer {
            log("flattenAndUpload: defer — dismissing editor, resetting inFlight")
            editor.dismiss()
            inFlight = false
        }
        do {
            editor.setStatus("Rendering…")
            let png = try Renderer.flatten(doc)
            editor.setStatus("Uploading…")
            let wallet = try WalletProvider.wallet()
            let rpc = HTTPEthereumRPC(endpoint: URL(string: "https://sepolia.base.org")!)
            let payment = PaymentClient(
                wallet: wallet, rpc: rpc,
                capUSD: Decimal(string: "0.50")!,
                receiptPoll: ReceiptPollPolicy(interval: 2.0, timeout: 120.0)
            )
            let mcp = MCPClient(
                transport: StreamableHTTPTransport(
                    endpoint: URL(string: "https://api.stage-cloudup.com/mcp/public")!),
                clientName: "cloudup-snap"
            )
            let uploader = Uploader(mcp: mcp, payment: payment)
            log("flattenAndUpload: calling Uploader.upload (\(png.count) bytes)")
            let url = try await uploader.upload(data: png, filename: "screenshot.png", mime: "image/png")
            log("flattenAndUpload: got url \(url)")
            clipboard.copy(url)
            await HistoryStore.shared.append(HistoryEntry(
                url: url.absoluteString,
                originalFilename: "screenshot.png"
            ))
            NSWorkspace.shared.open(url)
            // Fire-and-forget the toast so the upload flow can't block on
            // a never-resolving notification authorization prompt.
            Task { await NotificationService.shared.toast(title: "Copied", body: url.absoluteString) }
            log("flattenAndUpload: success")
        } catch let e as PaymentError {
            await handlePaymentError(e)
        } catch {
            log("upload failed: \(error)")
            await NotificationService.shared.toast(title: "Upload failed", body: "\(error)")
            showFailureAlert(title: "Upload failed", message: "\(error)")
        }
    }

    private func handlePaymentError(_ e: PaymentError) async {
        log("handlePaymentError: \(e)")
        let friendly = e.description
        // For payment / wallet-balance failures the user needs to take a
        // concrete action (add testnet crypto), so we open the FundingPanel
        // — it shows the address, balances, and direct links to faucets, plus
        // a "retry" button. No extra alert; the panel itself is the message.
        if isFundingProblem(e) {
            do {
                let wallet = try WalletProvider.wallet()
                let rpc = HTTPEthereumRPC(endpoint: URL(string: "https://sepolia.base.org")!)
                let usdcContract = EthereumAddress(bytes: try Data(hexString: "0x036CbD53842c5426634e7929541eC2318f3dCF7e"))
                async let usdc = wallet.balanceUSDC(contract: usdcContract, decimals: 6, rpc: rpc)
                async let eth = wallet.balanceETH(rpc: rpc)
                let (u, e2) = (try await usdc, try await eth)
                log("handlePaymentError: opening FundingPanel (USDC=\(u), ETH=\(e2))")
                funding.present(
                    address: wallet.address.hexString(),
                    balanceUSDC: u,
                    balanceETH: e2,
                    reason: friendly
                )
            } catch {
                log("handlePaymentError: couldn't read wallet \(error)")
                showFailureAlert(title: "Upload failed", message: "\(friendly)\n\n(Also couldn't read wallet balance: \(error.localizedDescription))")
            }
            return
        }
        // Non-funding payment errors (malformed challenge, unrecognized method,
        // generic .other): surface a modal alert with the friendly description.
        await NotificationService.shared.toast(title: "Upload failed", body: friendly)
        showFailureAlert(title: "Upload failed", message: friendly)
    }

    /// True if the error suggests the user should add crypto to the wallet.
    private func isFundingProblem(_ e: PaymentError) -> Bool {
        switch e {
        case .settlementReverted, .settlementTimeout, .insufficientFunds, .paymentRequired:
            return true
        default:
            return false
        }
    }

    /// Show a NSAlert on the main thread so the user always sees the failure
    /// reason (independent of whether notifications are authorized).
    private func showFailureAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - MP4 recording

    public func startRecording(fullScreen: Bool) {
        log("startRecording fullScreen=\(fullScreen) inFlight=\(inFlight)")
        if inFlight {
            log("forcing reset of stuck inFlight state")
            stopRecorderAndDismissHUD()
            editor.dismiss()
            inFlight = false
        }
        inFlight = true
        if fullScreen {
            beginFullScreenRecording()
        } else {
            regionOverlay.present { [weak self] selectedRect in
                guard let self else { return }
                guard let rect = selectedRect else { self.inFlight = false; return }
                Task { await self.beginRegionRecording(rect: rect) }
            }
        }
    }

    private func beginFullScreenRecording() {
        displaySelectionPanel.present { [weak self] screen in
            guard let self else { return }
            guard let screen else {
                self.log("beginFullScreenRecording: screen selection cancelled")
                self.inFlight = false
                return
            }
            Task { await self.beginFullScreenRecording(on: screen) }
        }
    }

    private func beginFullScreenRecording(on screen: NSScreen) async {
        guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            log("beginFullScreenRecording: no displayID")
            inFlight = false; return
        }
        log("beginFullScreenRecording: selected display \(displayID) (screen frame \(screen.frame))")
        await beginRecording(
            options: ScreenRecorder.Options(
                displayID: displayID,
                sourceRect: nil,
                pixelScale: screen.backingScaleFactor),
            highlightRect: nil)
    }

    private func beginRegionRecording(rect: CGRect) async {
        guard let screen = NSScreen.screens.first(where: { NSIntersectsRect($0.frame, rect) })
                ?? NSScreen.main,
              let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            log("beginRegionRecording: no displayID")
            inFlight = false; return
        }
        let localX = rect.origin.x - screen.frame.origin.x
        let localY = screen.frame.maxY - rect.maxY
        let local = CGRect(x: localX, y: localY, width: rect.width, height: rect.height)
        await beginRecording(
            options: ScreenRecorder.Options(
                displayID: displayID,
                sourceRect: local,
                pixelScale: screen.backingScaleFactor),
            highlightRect: rect)
    }

    private func beginRecording(options: ScreenRecorder.Options, highlightRect: CGRect?) async {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cloudup-snap-\(UUID().uuidString).mp4")
        // Build the recorder up-front so pause/resume/stop callbacks all have
        // something to talk to, but DON'T start the SCStream yet — the user
        // hits Record on the HUD to begin capturing.
        self.recorder = ScreenRecorder()
        self.pendingRecordingOptions = options
        self.pendingRecordingOutputURL = url
        self.pendingRecordingUsesMicrophone = UserDefaults.standard.bool(forKey: recordingMicrophoneDefaultsKey)
        if let rect = highlightRect {
            recordingFrame.present(rect: rect)
        }
        recordingHUD.present(initialMicrophoneEnabled: pendingRecordingUsesMicrophone, callbacks: RecordingHUD.Callbacks(
            onRecord: { [weak self] in Task { await self?.handleRecordTapped() } },
            onPause:  { [weak self] in self?.handlePauseTapped() },
            onResume: { [weak self] in self?.handleResumeTapped() },
            onStop:   { [weak self] in Task { await self?.finishRecording() } },
            onCancel: { [weak self] in self?.handleCancelRecording() },
            onMicrophoneChanged: { [weak self] enabled in
                guard let self else { return }
                self.pendingRecordingUsesMicrophone = enabled
                UserDefaults.standard.set(enabled, forKey: self.recordingMicrophoneDefaultsKey)
            }
        ))
    }

    private func handleRecordTapped() async {
        guard let recorder = self.recorder,
              let options = self.pendingRecordingOptions,
              let url = self.pendingRecordingOutputURL else {
            log("handleRecordTapped: no pending recorder/options")
            return
        }
        do {
            let excluded = [recordingHUD.windowID].compactMap { $0 }
            try await recorder.start(
                options: options,
                outputURL: url,
                excludingWindowIDs: excluded,
                recordsMicrophone: pendingRecordingUsesMicrophone)
        } catch {
            log("recorder.start error: \(error)")
            await NotificationService.shared.toast(title: "Recording failed", body: "\(error)")
            stopRecorderAndDismissHUD()
            inFlight = false
            return
        }
        // Clear the pending fields once start has succeeded.
        pendingRecordingOptions = nil
        pendingRecordingOutputURL = nil
        pendingRecordingUsesMicrophone = false
        recordingHUD.setState(.recording)

        let cap = maxRecordingSeconds
        recordingMaxDurationTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(cap * 1_000_000_000))
            if Task.isCancelled { return }
            await self?.finishRecording()
        }
    }

    private func handlePauseTapped() {
        recorder?.pause()
        recordingHUD.setState(.paused)
    }

    private func handleResumeTapped() {
        recorder?.resume()
        recordingHUD.setState(.recording)
    }

    private func handleCancelRecording() {
        log("handleCancelRecording")
        // Cancel from the ready state — nothing to upload, no temp file to keep.
        if let url = pendingRecordingOutputURL {
            try? FileManager.default.removeItem(at: url)
        }
        pendingRecordingOptions = nil
        pendingRecordingOutputURL = nil
        pendingRecordingUsesMicrophone = false
        recordingFrame.dismiss()
        recordingHUD.dismiss()
        recorder = nil
        inFlight = false
    }

    private func finishRecording() async {
        guard let recorder = self.recorder else { return }
        self.recorder = nil
        recordingMaxDurationTask?.cancel()
        recordingMaxDurationTask = nil
        recordingHUD.dismiss()
        recordingFrame.dismiss()
        do {
            let url = try await recorder.stop()
            log("recording stopped, file=\(url.path)")
            // Hand off to the preview window; only upload if the user confirms.
            recordingEditor.present(fileURL: url) { [weak self] confirmedURL in
                guard let self else { return }
                guard let confirmedURL else {
                    self.log("recording cancelled from preview")
                    self.inFlight = false
                    return
                }
                Task { await self.uploadRecording(at: confirmedURL) }
            }
        } catch {
            log("recorder.stop error: \(error)")
            await NotificationService.shared.toast(title: "Recording failed", body: "\(error)")
            inFlight = false
        }
    }

    private func stopRecorderAndDismissHUD() {
        recordingMaxDurationTask?.cancel()
        recordingMaxDurationTask = nil
        recordingHUD.dismiss()
        recordingFrame.dismiss()
        if let r = recorder {
            self.recorder = nil
            Task { _ = try? await r.stop() }
        }
    }

    private func uploadRecording(at fileURL: URL) async {
        defer {
            recordingEditor.dismiss()
            inFlight = false
            try? FileManager.default.removeItem(at: fileURL)
        }
        do {
            let data = try Data(contentsOf: fileURL)
            log("uploadRecording: \(data.count) bytes from \(fileURL.lastPathComponent)")
            recordingEditor.setStatus("Uploading…", busy: true)
            let wallet = try WalletProvider.wallet()
            let rpc = HTTPEthereumRPC(endpoint: URL(string: "https://sepolia.base.org")!)
            let payment = PaymentClient(
                wallet: wallet, rpc: rpc,
                capUSD: Decimal(string: "0.50")!,
                receiptPoll: ReceiptPollPolicy(interval: 2.0, timeout: 120.0)
            )
            let mcp = MCPClient(
                transport: StreamableHTTPTransport(
                    endpoint: URL(string: "https://api.stage-cloudup.com/mcp/public")!),
                clientName: "cloudup-snap"
            )
            let uploader = Uploader(mcp: mcp, payment: payment)
            let ext = fileURL.pathExtension.isEmpty ? "mp4" : fileURL.pathExtension.lowercased()
            let mime: String
            switch ext {
            case "gif":  mime = "image/gif"
            case "mp4":  mime = "video/mp4"
            case "mov":  mime = "video/quicktime"
            default:     mime = "application/octet-stream"
            }
            let filename = "recording-\(Int(Date().timeIntervalSince1970)).\(ext)"
            // Recordings (and converted GIFs) go through begin_upload/PUT/
            // complete_upload so the bytes bypass the JSON-RPC body and the
            // proxy's request-size cap.
            let url = try await uploader.uploadLarge(data: data, filename: filename, mime: mime)
            log("uploadRecording: got url \(url)")
            clipboard.copy(url)
            await HistoryStore.shared.append(HistoryEntry(
                url: url.absoluteString,
                originalFilename: filename
            ))
            NSWorkspace.shared.open(url)
            Task { await NotificationService.shared.toast(title: "Copied", body: url.absoluteString) }
        } catch let e as PaymentError {
            await handlePaymentError(e)
        } catch {
            log("recording upload failed: \(error)")
            await NotificationService.shared.toast(title: "Upload failed", body: "\(error)")
            showFailureAlert(title: "Upload failed", message: "\(error)")
        }
    }

    public func openFundingPanel() {
        Task {
            do {
                let wallet = try WalletProvider.wallet()
                let rpc = HTTPEthereumRPC(endpoint: URL(string: "https://sepolia.base.org")!)
                let usdcContract = EthereumAddress(bytes: try Data(hexString: "0x036CbD53842c5426634e7929541eC2318f3dCF7e"))
                async let usdc = wallet.balanceUSDC(contract: usdcContract, decimals: 6, rpc: rpc)
                async let eth = wallet.balanceETH(rpc: rpc)
                let (u, e) = (try await usdc, try await eth)
                funding.present(address: wallet.address.hexString(), balanceUSDC: u, balanceETH: e)
            } catch {}
        }
    }
}
