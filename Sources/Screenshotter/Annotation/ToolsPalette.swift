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
    @Binding public var strokeIsDashed: Bool
    @Binding public var stickerID: String
    public var onUpload: () -> Void
    public var onCancel: () -> Void
    public var onUndo: () -> Void
    public var onRedo: () -> Void

    @State private var showingStickerPicker: Bool = false
    @State private var showingStrokePicker: Bool = false

    public init(
        selectedTool: Binding<Tool>,
        strokeColor: Binding<Color>,
        strokeWidth: Binding<CGFloat>,
        strokeIsDashed: Binding<Bool>,
        stickerID: Binding<String>,
        onUpload: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onUndo: @escaping () -> Void,
        onRedo: @escaping () -> Void
    ) {
        self._selectedTool = selectedTool
        self._strokeColor = strokeColor
        self._strokeWidth = strokeWidth
        self._strokeIsDashed = strokeIsDashed
        self._stickerID = stickerID
        self.onUpload = onUpload
        self.onCancel = onCancel
        self.onUndo = onUndo
        self.onRedo = onRedo
    }

    public var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Tool.allCases.filter { $0 != .sticker }) { tool in
                        toolButton(tool)
                    }
                    toolButton(.sticker)
                        .popover(isPresented: $showingStickerPicker, arrowEdge: .bottom) {
                            StickerPicker(
                                selectedID: $stickerID,
                                onSelect: { id in
                                    stickerID = id
                                    showingStickerPicker = false
                                }
                            )
                        }

                    Divider().frame(height: 24)

                    // Color picker (no native label — provide a tooltip instead)
                    ColorPicker("", selection: $strokeColor)
                        .labelsHidden()
                        .frame(width: 28)
                        .help("Stroke color")

                    // Stroke style: opens a popover with horizontal-bar previews
                    // grouped into sections (solid widths, dashed). Trigger
                    // button shows a live preview of the current stroke.
                    Button {
                        showingStrokePicker.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            StrokeSwatch(width: strokeWidth, isDashed: strokeIsDashed, color: strokeColor)
                                .frame(width: 32, height: 12)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.bordered)
                    .fixedSize()
                    .help("Stroke style")
                    .popover(isPresented: $showingStrokePicker, arrowEdge: .bottom) {
                        StrokeStylePicker(
                            width: $strokeWidth,
                            isDashed: $strokeIsDashed,
                            color: strokeColor,
                            onClose: { showingStrokePicker = false }
                        )
                    }

                    Divider().frame(height: 24)

                    Button(action: onUndo) { Image(systemName: "arrow.uturn.backward") }
                        .keyboardShortcut("z")
                        .help("Undo (⌘Z)")
                    Button(action: onRedo) { Image(systemName: "arrow.uturn.forward") }
                        .keyboardShortcut("z", modifiers: [.command, .shift])
                        .help("Redo (⌘⇧Z)")
                }
                .padding(.horizontal, 4)
            }
            .layoutPriority(0)

            HStack(spacing: 8) {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.escape, modifiers: [])
                    .help("Discard this annotation")
                Button("Upload", action: onUpload)
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
                    .help("Upload to Cloudup (⌘↩)")
            }
            .padding(.leading, 8)
            .layoutPriority(1)
        }
        .padding(.horizontal, 8).padding(.vertical, 8)
        .background(.thinMaterial)
    }

    @ViewBuilder
    private func toolButton(_ tool: Tool) -> some View {
        Button {
            if tool == .sticker {
                if selectedTool == .sticker {
                    showingStickerPicker.toggle()
                } else {
                    selectedTool = .sticker
                    showingStickerPicker = true
                }
            } else {
                selectedTool = tool
            }
        } label: {
            Image(systemName: tool.systemImage)
                .frame(width: 28, height: 28)
                .background(selectedTool == tool ? Color.accentColor.opacity(0.2) : .clear)
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .help(tool.displayName)
    }
}

/// Grid of built-in stickers shown in a popover off the sticker tool button.
struct StickerPicker: View {
    @Binding var selectedID: String
    var onSelect: (String) -> Void

    private let columns = Array(repeating: GridItem(.fixed(36), spacing: 6), count: 8)

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Stickers.allIDs, id: \.self) { id in
                    Button {
                        onSelect(id)
                    } label: {
                        Group {
                            if let img = Stickers.image(for: id) {
                                Image(decorative: img, scale: 1).resizable().scaledToFit()
                            } else {
                                Color.clear
                            }
                        }
                        .frame(width: 32, height: 32)
                        .padding(2)
                        .background(selectedID == id ? Color.accentColor.opacity(0.25) : .clear)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .help(id)
                }
            }
            .padding(8)
        }
        .frame(width: 320, height: 240)
    }
}

/// Single horizontal-line preview at a given stroke width and dash pattern.
struct StrokeSwatch: View {
    let width: CGFloat
    let isDashed: Bool
    let color: Color
    var body: some View {
        GeometryReader { geo in
            let mid = geo.size.height / 2
            Path { p in
                p.move(to: CGPoint(x: 0, y: mid))
                p.addLine(to: CGPoint(x: geo.size.width, y: mid))
            }
            .stroke(color, style: StrokeStyle(
                lineWidth: width,
                lineCap: .round,
                dash: isDashed ? [max(2, width * 2), max(2, width * 2)] : []
            ))
        }
    }
}

/// Popover-style stroke picker that renders each option as a visual bar,
/// grouped into sections (solid widths, dashed) with a leading checkmark
/// next to the currently-selected option. Modeled on macOS Markup's stroke
/// dropdown.
struct StrokeStylePicker: View {
    @Binding var width: CGFloat
    @Binding var isDashed: Bool
    var color: Color
    var onClose: () -> Void

    private static let solidWidths: [CGFloat] = [1, 2, 3, 4, 6, 8, 12]
    private static let dashedWidths: [CGFloat] = [3, 6]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Self.solidWidths, id: \.self) { w in
                row(width: w, isDashed: false)
            }
            Divider().padding(.vertical, 4)
            ForEach(Self.dashedWidths, id: \.self) { w in
                row(width: w, isDashed: true)
            }
        }
        .padding(.vertical, 6)
        .frame(width: 170)
    }

    @ViewBuilder
    private func row(width w: CGFloat, isDashed dashed: Bool) -> some View {
        let isCurrent = w == width && dashed == isDashed
        Button {
            width = w
            isDashed = dashed
            onClose()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 14)
                    .opacity(isCurrent ? 1 : 0)
                StrokeSwatch(width: w, isDashed: dashed, color: color)
                    .frame(maxWidth: .infinity, minHeight: 16)
                Spacer().frame(width: 14)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

extension Tool {
    var displayName: String {
        switch self {
        case .select:  return "Select / move (last 3)"
        case .arrow:   return "Arrow"
        case .line:    return "Line"
        case .rect:    return "Rectangle"
        case .ellipse: return "Ellipse"
        case .text:    return "Text"
        case .pen:     return "Freehand pen"
        case .blur:    return "Blur / redact"
        case .sticker: return "Sticker"
        }
    }
}
