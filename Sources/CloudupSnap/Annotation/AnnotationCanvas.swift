import SwiftUI
import CoreGraphics
import AppKit

public struct AnnotationCanvas: View {
    @Binding public var document: AnnotationDocument
    public var tool: Tool
    public var strokeColor: Color
    public var strokeWidth: CGFloat
    public var isDashed: Bool
    public var stickerID: String
    /// Display scale factor — the canvas is rendered at `document.size * displayScale`
    /// points but all internal coordinates (gestures, element positions) remain in
    /// document space, so annotations land where the user expects regardless of
    /// the current zoom.
    public var displayScale: CGFloat
    public var onCommit: (Element) -> Void
    public var onUpdate: (Element) -> Void
    public var onRemove: (UUID) -> Void

    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?
    @State private var penPoints: [CGPoint] = []
    @State private var editingTextID: UUID?
    @State private var editingContent: String = ""
    @FocusState private var textFieldFocused: Bool

    // Move state for the Select tool. Only the last 3 elements are movable.
    public static let maxMovableCount = 3
    @State private var movingID: UUID?
    @State private var moveAnchor: CGPoint?
    @State private var moveOffset: CGSize = .zero

    public init(
        document: Binding<AnnotationDocument>,
        tool: Tool,
        strokeColor: Color,
        strokeWidth: CGFloat,
        isDashed: Bool = false,
        stickerID: String = "emoji-1",
        displayScale: CGFloat = 1.0,
        onCommit: @escaping (Element) -> Void,
        onUpdate: @escaping (Element) -> Void = { _ in },
        onRemove: @escaping (UUID) -> Void = { _ in }
    ) {
        self._document = document
        self.tool = tool
        self.strokeColor = strokeColor
        self.strokeWidth = strokeWidth
        self.isDashed = isDashed
        self.stickerID = stickerID
        self.displayScale = displayScale
        self.onCommit = onCommit
        self.onUpdate = onUpdate
        self.onRemove = onRemove
    }

    public var body: some View {
        let displayW = document.size.width * displayScale
        let displayH = document.size.height * displayScale
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                // Scale the drawing context so we can draw in document coordinates;
                // the GraphicsContext will render scaled to the canvas's actual size.
                var ctx = context
                ctx.scaleBy(x: displayScale, y: displayScale)

                if let bg = document.background {
                    ctx.draw(Image(decorative: bg, scale: 1),
                             in: CGRect(origin: .zero, size: document.size))
                }
                for element in document.elements {
                    if element.id == editingTextID { continue }
                    let toDraw: Element = (element.id == movingID)
                        ? element.translated(by: CGVector(dx: moveOffset.width, dy: moveOffset.height))
                        : element
                    drawElement(toDraw, in: ctx)
                    if element.id == movingID {
                        let outline = Path(toDraw.frame.insetBy(dx: -2, dy: -2))
                        ctx.stroke(outline,
                                   with: .color(.accentColor),
                                   style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                }
                if let s = dragStart, let c = dragCurrent, movingID == nil {
                    drawPreview(start: s, current: c, in: ctx)
                }
            }
            .frame(width: displayW, height: displayH)
            .background(Color.white)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if editingTextID != nil { return }
                        // Convert gesture coords from canvas (display) space to document space.
                        let docStart = CGPoint(x: value.startLocation.x / displayScale,
                                               y: value.startLocation.y / displayScale)
                        let docLoc = CGPoint(x: value.location.x / displayScale,
                                             y: value.location.y / displayScale)
                        if tool == .select {
                            if movingID == nil, moveAnchor == nil {
                                moveAnchor = docStart
                                movingID = hitTestMovable(at: docStart)
                            }
                            if movingID != nil {
                                moveOffset = CGSize(width: docLoc.x - docStart.x,
                                                    height: docLoc.y - docStart.y)
                            }
                            return
                        }
                        if dragStart == nil { dragStart = docStart }
                        dragCurrent = docLoc
                        if tool == .pen { penPoints.append(docLoc) }
                    }
                    .onEnded { value in
                        if editingTextID != nil { return }
                        let docLoc = CGPoint(x: value.location.x / displayScale,
                                             y: value.location.y / displayScale)
                        if tool == .select {
                            if let id = movingID,
                               let el = document.elements.first(where: { $0.id == id }),
                               moveOffset != .zero {
                                let moved = el.translated(by: CGVector(dx: moveOffset.width, dy: moveOffset.height))
                                onUpdate(moved)
                            }
                            movingID = nil
                            moveAnchor = nil
                            moveOffset = .zero
                            return
                        }
                        if let s = dragStart {
                            commitElement(from: s, to: docLoc)
                        }
                        dragStart = nil; dragCurrent = nil; penPoints.removeAll()
                    }
            )

            // Overlay editable text field — positioned and sized in display space
            // so it visually lines up with the scaled drawing.
            if let id = editingTextID,
               let el = document.elements.first(where: { $0.id == id }),
               case .text(let frame, _) = el.payload {
                TextField("Type here", text: $editingContent, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: el.style.fontSize * displayScale))
                    .foregroundColor(Color(cgColor: el.style.strokeColor))
                    .padding(2)
                    .background(Color.white.opacity(0.6))
                    .frame(width: max(120, frame.width) * displayScale, alignment: .topLeading)
                    .offset(x: frame.origin.x * displayScale, y: frame.origin.y * displayScale)
                    .focused($textFieldFocused)
                    .onSubmit { commitTextEdit() }
                    .onExitCommand { commitTextEdit() }
                    .task {
                        try? await Task.sleep(nanoseconds: 50_000_000)
                        textFieldFocused = true
                    }
            }
        }
        .frame(width: displayW, height: displayH)
    }

    /// Returns the id of the topmost movable element under `point`. Only the
    /// last `maxMovableCount` elements in the document are considered movable.
    private func hitTestMovable(at point: CGPoint) -> UUID? {
        let tail = document.elements.suffix(Self.maxMovableCount)
        for element in tail.reversed() where element.hitTest(point) {
            return element.id
        }
        return nil
    }

    private func commitTextEdit() {
        guard let id = editingTextID else { return }
        if let idx = document.elements.firstIndex(where: { $0.id == id }) {
            let old = document.elements[idx]
            if editingContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                onRemove(id)
            } else if case .text(let frame, _) = old.payload {
                var updated = old
                updated.payload = .text(frame: frame, content: editingContent)
                onUpdate(updated)
            }
        }
        editingTextID = nil
        editingContent = ""
        textFieldFocused = false
    }

    private func currentStyle() -> ElementStyle {
        var s = ElementStyle.defaultStroke
        s.strokeColor = NSColor(strokeColor).cgColor
        s.strokeWidth = strokeWidth
        s.isDashed = isDashed
        return s
    }

    private func commitElement(from start: CGPoint, to end: CGPoint) {
        let frame = CGRect(
            x: min(start.x, end.x), y: min(start.y, end.y),
            width: abs(end.x - start.x), height: abs(end.y - start.y)
        )
        let style = currentStyle()
        let element: Element?
        switch tool {
        case .select: element = nil
        case .arrow: element = Element.arrow(start: start, end: end, style: style)
        case .line: element = Element.line(start: start, end: end, style: style)
        case .rect: element = Element.rect(frame: frame, style: style)
        case .ellipse: element = Element.ellipse(frame: frame, style: style)
        case .text:
            // Ensure a minimum frame so the TextField has somewhere to land.
            var f = frame
            if f.width < 60 { f.size.width = 160 }
            if f.height < 20 { f.size.height = 28 }
            let placed = Element.text(frame: f, content: "", style: style)
            onCommit(placed)
            editingTextID = placed.id
            editingContent = ""
            return
        case .pen: element = Element.pen(frame: frame, points: penPoints, style: style)
        case .blur: element = Element.blur(frame: frame)
        case .sticker:
            // Stickers are square bitmaps — always commit a square frame so
            // they don't get stretched. A click places a default-size sticker
            // centered on the point; a drag uses max(|dx|, |dy|) as the side
            // length, anchored at the drag start.
            let defaultSize: CGFloat = 64
            let dx = end.x - start.x
            let dy = end.y - start.y
            let dragDistance = hypot(dx, dy)
            let f: CGRect
            if dragDistance < 8 {
                f = CGRect(x: end.x - defaultSize / 2,
                           y: end.y - defaultSize / 2,
                           width: defaultSize, height: defaultSize)
            } else {
                let side = max(abs(dx), abs(dy), 24)
                let originX = dx >= 0 ? start.x : start.x - side
                let originY = dy >= 0 ? start.y : start.y - side
                f = CGRect(x: originX, y: originY, width: side, height: side)
            }
            element = Element.sticker(frame: f, id: stickerID)
        }
        if let e = element { onCommit(e) }
    }

    private func drawElement(_ element: Element, in context: GraphicsContext) {
        let color = Color(cgColor: element.style.strokeColor)
        let style = strokeStyle(for: element.style)
        switch element.payload {
        case .line(let s, let e):
            var path = Path(); path.move(to: s); path.addLine(to: e)
            context.stroke(path, with: .color(color), style: style)
        case .arrow(let s, let e):
            context.stroke(arrowPath(from: s, to: e, headLength: max(10, element.style.strokeWidth * 4)),
                           with: .color(color), style: style)
        case .rect(let f):
            context.stroke(Path(roundedRect: f, cornerRadius: 0),
                           with: .color(color), style: style)
        case .ellipse(let f):
            context.stroke(Path(ellipseIn: f),
                           with: .color(color), style: style)
        case .text(let f, let content):
            context.draw(
                Text(content)
                    .font(.system(size: element.style.fontSize))
                    .foregroundColor(color),
                in: f
            )
        case .pen(_, let points):
            var path = Path()
            if let first = points.first {
                path.move(to: first)
                for p in points.dropFirst() { path.addLine(to: p) }
            }
            context.stroke(path, with: .color(color), style: style)
        case .blur(let f):
            context.fill(Path(f), with: .color(.gray.opacity(0.3)))
            context.stroke(Path(f), with: .color(.gray), lineWidth: 1)
        case .sticker(let f, let id):
            if let img = Stickers.image(for: id) {
                context.draw(Image(decorative: img, scale: 1), in: f)
            }
        }
    }

    private func drawPreview(start: CGPoint, current: CGPoint, in context: GraphicsContext) {
        let elStyle = currentStyle()
        let color = Color(cgColor: elStyle.strokeColor)
        let stroke = strokeStyle(for: elStyle)
        switch tool {
        case .arrow:
            context.stroke(arrowPath(from: start, to: current, headLength: max(10, elStyle.strokeWidth * 4)),
                           with: .color(color), style: stroke)
        case .line:
            var p = Path(); p.move(to: start); p.addLine(to: current)
            context.stroke(p, with: .color(color), style: stroke)
        case .rect:
            context.stroke(Path(CGRect(x: min(start.x, current.x), y: min(start.y, current.y),
                width: abs(current.x - start.x), height: abs(current.y - start.y))),
                with: .color(color), style: stroke)
        case .ellipse:
            context.stroke(Path(ellipseIn: CGRect(x: min(start.x, current.x), y: min(start.y, current.y),
                width: abs(current.x - start.x), height: abs(current.y - start.y))),
                with: .color(color), style: stroke)
        case .pen:
            var p = Path()
            if let first = penPoints.first { p.move(to: first); for pt in penPoints.dropFirst() { p.addLine(to: pt) } }
            context.stroke(p, with: .color(color), style: stroke)
        case .sticker:
            // Mirror commitElement: preview as a square anchored at drag start.
            let dx = current.x - start.x
            let dy = current.y - start.y
            let side = max(abs(dx), abs(dy))
            let originX = dx >= 0 ? start.x : start.x - side
            let originY = dy >= 0 ? start.y : start.y - side
            let f = CGRect(x: originX, y: originY, width: side, height: side)
            if let img = Stickers.image(for: stickerID), side > 4 {
                context.draw(Image(decorative: img, scale: 1), in: f)
            }
        default: break
        }
    }

    private func strokeStyle(for style: ElementStyle) -> StrokeStyle {
        StrokeStyle(
            lineWidth: style.strokeWidth,
            lineCap: .round,
            lineJoin: .round,
            dash: style.isDashed ? style.dashLengths : []
        )
    }
}

/// Build a Path for an arrow from `start` to `end` with a triangular-style
/// arrowhead of `headLength` points at the end.
func arrowPath(from start: CGPoint, to end: CGPoint, headLength: CGFloat) -> Path {
    var path = Path()
    path.move(to: start)
    path.addLine(to: end)
    let dx = end.x - start.x
    let dy = end.y - start.y
    guard dx != 0 || dy != 0 else { return path }
    let angle = atan2(dy, dx)
    let headAngle = CGFloat.pi / 7  // ~25.7° each side
    let h1 = CGPoint(
        x: end.x - headLength * cos(angle - headAngle),
        y: end.y - headLength * sin(angle - headAngle)
    )
    let h2 = CGPoint(
        x: end.x - headLength * cos(angle + headAngle),
        y: end.y - headLength * sin(angle + headAngle)
    )
    path.move(to: h1)
    path.addLine(to: end)
    path.addLine(to: h2)
    return path
}
