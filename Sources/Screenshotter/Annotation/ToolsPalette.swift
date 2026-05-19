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

public struct StrokePreset: Identifiable, Hashable, Sendable {
    public var id: String { "\(width)-\(isDashed)" }
    public let width: CGFloat
    public let isDashed: Bool

    public static let all: [StrokePreset] = [
        StrokePreset(width: 2, isDashed: false),
        StrokePreset(width: 4, isDashed: false),
        StrokePreset(width: 8, isDashed: false),
        StrokePreset(width: 2, isDashed: true),
        StrokePreset(width: 4, isDashed: true),
        StrokePreset(width: 8, isDashed: true),
    ]
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

                    // Stroke style: button-styled dropdown with 6 visual presets
                    // (3 solid weights + 3 dashed). Trigger button shows a live
                    // preview of the currently-selected stroke.
                    Menu {
                        ForEach(StrokePreset.all) { preset in
                            Button {
                                strokeWidth = preset.width
                                strokeIsDashed = preset.isDashed
                            } label: {
                                StrokePresetLabel(
                                    width: preset.width,
                                    isDashed: preset.isDashed,
                                    color: strokeColor,
                                    isCurrent: preset.width == strokeWidth && preset.isDashed == strokeIsDashed
                                )
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            StrokeSwatch(width: strokeWidth, isDashed: strokeIsDashed, color: strokeColor)
                                .frame(width: 32, height: 12)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                    }
                    .menuStyle(.button)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Stroke style")

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

/// One row of the stroke dropdown — pure visual line preview + checkmark.
struct StrokePresetLabel: View {
    let width: CGFloat
    let isDashed: Bool
    let color: Color
    let isCurrent: Bool
    var body: some View {
        HStack(spacing: 8) {
            StrokeSwatch(width: width, isDashed: isDashed, color: color)
                .frame(width: 96, height: 14)
            if isCurrent {
                Image(systemName: "checkmark").foregroundColor(.secondary)
            } else {
                Image(systemName: "checkmark").opacity(0)
            }
        }
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
