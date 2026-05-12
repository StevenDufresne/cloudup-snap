import SwiftUI
import AppKit

public enum Tool: String, CaseIterable, Identifiable, Sendable {
    case select, arrow, line, rect, ellipse, text, pen, blur, sticker
    public var id: String { rawValue }
    public var systemImage: String {
        switch self {
        case .select: return "cursorarrow"
        case .arrow: return "arrow.up.right"
        case .line: return "line.diagonal"
        case .rect: return "rectangle"
        case .ellipse: return "circle"
        case .text: return "textformat"
        case .pen: return "pencil.tip"
        case .blur: return "drop.fill"
        case .sticker: return "smiley"
        }
    }
}

public struct ToolsPalette: View {
    @Binding public var selectedTool: Tool
    @Binding public var strokeColor: Color
    @Binding public var strokeWidth: CGFloat
    public var onUpload: () -> Void
    public var onCancel: () -> Void
    public var onUndo: () -> Void
    public var onRedo: () -> Void

    public init(
        selectedTool: Binding<Tool>,
        strokeColor: Binding<Color>,
        strokeWidth: Binding<CGFloat>,
        onUpload: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onUndo: @escaping () -> Void,
        onRedo: @escaping () -> Void
    ) {
        self._selectedTool = selectedTool
        self._strokeColor = strokeColor
        self._strokeWidth = strokeWidth
        self.onUpload = onUpload
        self.onCancel = onCancel
        self.onUndo = onUndo
        self.onRedo = onRedo
    }

    public var body: some View {
        HStack(spacing: 8) {
            ForEach(Tool.allCases) { tool in
                Button { selectedTool = tool } label: {
                    Image(systemName: tool.systemImage)
                        .frame(width: 28, height: 28)
                        .background(selectedTool == tool ? Color.accentColor.opacity(0.2) : .clear)
                        .cornerRadius(4)
                }.buttonStyle(.plain)
            }
            Divider().frame(height: 24)
            ColorPicker("", selection: $strokeColor).labelsHidden().frame(width: 28)
            Stepper("", value: $strokeWidth, in: 1...12, step: 1).labelsHidden().frame(width: 28)
            Divider().frame(height: 24)
            Button(action: onUndo) { Image(systemName: "arrow.uturn.backward") }.keyboardShortcut("z")
            Button(action: onRedo) { Image(systemName: "arrow.uturn.forward") }.keyboardShortcut("z", modifiers: [.command, .shift])
            Spacer()
            Button("Cancel", action: onCancel).keyboardShortcut(.escape, modifiers: [])
            Button("Upload", action: onUpload).keyboardShortcut(.return).buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.thinMaterial)
    }
}
