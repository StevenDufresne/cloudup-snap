import AppKit
import SwiftUI
import CoreGraphics

@MainActor
public final class AnnotationEditorState: ObservableObject {
    @Published public var isUploading: Bool = false
    @Published public var statusMessage: String = ""
    public init() {}
}

@MainActor
public final class AnnotationEditor: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let state = AnnotationEditorState()
    private var completion: ((AnnotationDocument?) -> Void)?

    public override init() { super.init() }

    /// NSWindowDelegate — the user clicked the red title-bar close button.
    /// Treat it as a cancel: clear state and inform the coordinator with nil.
    public nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in self.handleCancel() }
    }

    public func present(background: CGImage, pixelScale: CGFloat = 1.0, completion: @escaping (AnnotationDocument?) -> Void) {
        self.completion = completion
        state.isUploading = false
        state.statusMessage = ""
        // Logical (point) size = pixel size / pixelScale. The canvas displays
        // at point size; the Renderer outputs at full pixel resolution.
        let size = CGSize(
            width: CGFloat(background.width) / pixelScale,
            height: CGFloat(background.height) / pixelScale
        )
        let doc = AnnotationDocument(background: background, size: size, pixelScale: pixelScale)
        let root = AnnotationEditorRoot(
            initialDoc: doc,
            state: state,
            onUpload: { [weak self] d in self?.handleUpload(d) },
            onCancel: { [weak self] in self?.handleCancel() }
        )
        let view = NSHostingView(rootView: root)
        let toolbarHeight: CGFloat = 44

        // Clamp the initial size to fit the current screen with some margin.
        let screen = NSScreen.main ?? NSScreen.screens.first
        let maxW = (screen?.visibleFrame.width ?? size.width) * 0.9
        let maxH = (screen?.visibleFrame.height ?? size.height) * 0.9
        let scaleDown = min(1, min(maxW / size.width, maxH / (size.height + toolbarHeight)))
        let initialW = max(size.width * scaleDown, 280)
        let initialH = size.height * scaleDown + toolbarHeight

        let win = NSWindow(
            contentRect: NSRect(origin: .zero, size: CGSize(width: initialW, height: initialH)),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false
        )
        // Manage the window's lifetime ourselves: when the user clicks the
        // red close button, NSWindow's default behavior is to RELEASE itself,
        // leaving us with a dangling pointer. Disable that, and rely on the
        // delegate's windowWillClose to clean up.
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.title = "Annotate"
        win.contentView = view
        win.contentMinSize = CGSize(width: 240, height: toolbarHeight + 60)
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = win
    }

    /// Called by the coordinator to update status visible inside the loading overlay.
    public func setStatus(_ message: String) {
        state.statusMessage = message
    }

    /// Close the editor — used by the coordinator after upload completes (success or failure).
    public func dismiss() {
        window?.orderOut(nil)
        window = nil
        completion = nil
        state.isUploading = false
    }

    // MARK: - Internal callbacks

    /// User clicked Upload. We do NOT close the window yet — instead we set the
    /// uploading state so the loading overlay shows, then hand the document to
    /// the coordinator. The coordinator calls `dismiss()` when the upload finishes.
    private func handleUpload(_ doc: AnnotationDocument) {
        state.isUploading = true
        state.statusMessage = "Uploading…"
        let cb = completion
        cb?(doc)
    }

    private func handleCancel() {
        let cb = completion
        completion = nil
        window?.orderOut(nil)
        window = nil
        cb?(nil)
    }
}

@MainActor
struct AnnotationEditorRoot: View {
    @State var document: AnnotationDocument
    @State var undoStack = UndoStack()
    @State var tool: Tool = .arrow
    @State var strokeColor: Color = Color(red: 1.0, green: 119.0/255, blue: 90.0/255)  // Cloudup #ff775a
    @State var strokeWidth: CGFloat = 4
    @State var strokeIsDashed: Bool = false
    @State var stickerID: String = "emoji-1"
    @ObservedObject var state: AnnotationEditorState
    let onUpload: (AnnotationDocument) -> Void
    let onCancel: () -> Void

    init(initialDoc: AnnotationDocument,
         state: AnnotationEditorState,
         onUpload: @escaping (AnnotationDocument) -> Void,
         onCancel: @escaping () -> Void) {
        self._document = State(initialValue: initialDoc)
        self.state = state
        self.onUpload = onUpload
        self.onCancel = onCancel
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                ToolsPalette(
                    selectedTool: $tool,
                    strokeColor: $strokeColor,
                    strokeWidth: $strokeWidth,
                    strokeIsDashed: $strokeIsDashed,
                    stickerID: $stickerID,
                    onUpload: { onUpload(document) },
                    onCancel: onCancel,
                    onUndo: { undoStack.undo(on: &document) },
                    onRedo: { undoStack.redo(on: &document) }
                )
                // Fit-to-window: scale the canvas to whatever space the window
                // gives us, capped at 1.0 (never upscale a small screenshot).
                GeometryReader { geo in
                    let scale = min(1.0, min(
                        geo.size.width / max(1, document.size.width),
                        geo.size.height / max(1, document.size.height)
                    ))
                    AnnotationCanvas(
                        document: $document,
                        tool: tool,
                        strokeColor: strokeColor,
                        strokeWidth: strokeWidth,
                        isDashed: strokeIsDashed,
                        stickerID: stickerID,
                        displayScale: scale,
                        onCommit: { e in undoStack.perform(.add(e), on: &document) },
                        onUpdate: { updated in
                            if let old = document.elements.first(where: { $0.id == updated.id }) {
                                undoStack.perform(.update(old: old, new: updated), on: &document)
                            }
                        },
                        onRemove: { id in
                            if let old = document.elements.first(where: { $0.id == id }) {
                                undoStack.perform(.remove(old), on: &document)
                            }
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
                .background(Color(white: 0.95))
            }
            .disabled(state.isUploading)

            if state.isUploading {
                Color.black.opacity(0.4).ignoresSafeArea()
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text(state.statusMessage.isEmpty ? "Uploading…" : state.statusMessage)
                        .font(.body)
                }
                .padding(24)
                .background(.thickMaterial)
                .cornerRadius(12)
                .shadow(radius: 12)
            }
        }
    }
}
