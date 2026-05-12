import AppKit
import SwiftUI
import CoreGraphics

@MainActor
public final class AnnotationEditor {
    private var window: NSWindow?
    private var completion: ((AnnotationDocument?) -> Void)?

    public init() {}

    public func present(background: CGImage, completion: @escaping (AnnotationDocument?) -> Void) {
        self.completion = completion
        let size = CGSize(width: background.width, height: background.height)
        let doc = AnnotationDocument(background: background, size: size)
        let root = AnnotationEditorRoot(
            initialDoc: doc,
            onUpload: { [weak self] d in self?.finish(d) },
            onCancel: { [weak self] in self?.finish(nil) }
        )
        let view = NSHostingView(rootView: root)
        let win = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        win.title = "Annotate"
        win.contentView = view
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = win
    }

    private func finish(_ doc: AnnotationDocument?) {
        window?.orderOut(nil)
        window = nil
        let cb = completion
        completion = nil
        cb?(doc)
    }
}

@MainActor
struct AnnotationEditorRoot: View {
    @State var document: AnnotationDocument
    @State var undoStack = UndoStack()
    @State var tool: Tool = .arrow
    @State var strokeColor: Color = .red
    @State var strokeWidth: CGFloat = 3
    let onUpload: (AnnotationDocument) -> Void
    let onCancel: () -> Void

    init(initialDoc: AnnotationDocument, onUpload: @escaping (AnnotationDocument) -> Void, onCancel: @escaping () -> Void) {
        self._document = State(initialValue: initialDoc)
        self.onUpload = onUpload
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 0) {
            ToolsPalette(
                selectedTool: $tool,
                strokeColor: $strokeColor,
                strokeWidth: $strokeWidth,
                onUpload: { onUpload(document) },
                onCancel: onCancel,
                onUndo: { undoStack.undo(on: &document) },
                onRedo: { undoStack.redo(on: &document) }
            )
            AnnotationCanvas(
                document: $document,
                tool: tool,
                strokeColor: strokeColor,
                strokeWidth: strokeWidth,
                onCommit: { e in undoStack.perform(.add(e), on: &document) }
            )
        }
    }
}
