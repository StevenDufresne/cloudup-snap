import SwiftUI
import CoreGraphics
import AppKit

public struct AnnotationCanvas: View {
    @Binding public var document: AnnotationDocument
    public var tool: Tool
    public var strokeColor: Color
    public var strokeWidth: CGFloat
    public var onCommit: (Element) -> Void

    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?
    @State private var penPoints: [CGPoint] = []

    public init(
        document: Binding<AnnotationDocument>,
        tool: Tool,
        strokeColor: Color,
        strokeWidth: CGFloat,
        onCommit: @escaping (Element) -> Void
    ) {
        self._document = document
        self.tool = tool
        self.strokeColor = strokeColor
        self.strokeWidth = strokeWidth
        self.onCommit = onCommit
    }

    public var body: some View {
        Canvas { context, size in
            if let bg = document.background {
                context.draw(Image(decorative: bg, scale: 1), in: CGRect(origin: .zero, size: size))
            }
            for element in document.elements {
                drawElement(element, in: context)
            }
            if let s = dragStart, let c = dragCurrent {
                drawPreview(start: s, current: c, in: context)
            }
        }
        .frame(width: document.size.width, height: document.size.height)
        .background(Color.white)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if dragStart == nil { dragStart = value.startLocation }
                    dragCurrent = value.location
                    if tool == .pen { penPoints.append(value.location) }
                }
                .onEnded { value in
                    if let s = dragStart {
                        commitElement(from: s, to: value.location)
                    }
                    dragStart = nil; dragCurrent = nil; penPoints.removeAll()
                }
        )
    }

    private func currentStyle() -> ElementStyle {
        var s = ElementStyle.defaultStroke
        s.strokeColor = NSColor(strokeColor).cgColor
        s.strokeWidth = strokeWidth
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
        case .arrow, .line: element = Element.line(start: start, end: end, style: style)
        case .rect: element = Element.rect(frame: frame, style: style)
        case .ellipse: element = Element.ellipse(frame: frame, style: style)
        case .text: element = Element.text(frame: frame, content: "Type here", style: style)
        case .pen: element = Element.pen(frame: frame, points: penPoints, style: style)
        case .blur: element = Element.blur(frame: frame)
        case .sticker: element = nil
        }
        if let e = element { onCommit(e) }
    }

    private func drawElement(_ element: Element, in context: GraphicsContext) {
        switch element.payload {
        case .line(let s, let e):
            var path = Path(); path.move(to: s); path.addLine(to: e)
            context.stroke(path, with: .color(Color(cgColor: element.style.strokeColor)),
                           lineWidth: element.style.strokeWidth)
        case .rect(let f):
            context.stroke(Path(roundedRect: f, cornerRadius: 0),
                           with: .color(Color(cgColor: element.style.strokeColor)),
                           lineWidth: element.style.strokeWidth)
        case .ellipse(let f):
            context.stroke(Path(ellipseIn: f),
                           with: .color(Color(cgColor: element.style.strokeColor)),
                           lineWidth: element.style.strokeWidth)
        case .text(let f, let content):
            context.draw(
                Text(content)
                    .font(.system(size: element.style.fontSize))
                    .foregroundColor(Color(cgColor: element.style.strokeColor)),
                in: f
            )
        case .pen(_, let points):
            var path = Path()
            if let first = points.first {
                path.move(to: first)
                for p in points.dropFirst() { path.addLine(to: p) }
            }
            context.stroke(path, with: .color(Color(cgColor: element.style.strokeColor)),
                           lineWidth: element.style.strokeWidth)
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
        let style = currentStyle()
        let color = Color(cgColor: style.strokeColor)
        switch tool {
        case .arrow, .line:
            var p = Path(); p.move(to: start); p.addLine(to: current)
            context.stroke(p, with: .color(color), lineWidth: style.strokeWidth)
        case .rect:
            context.stroke(Path(CGRect(x: min(start.x, current.x), y: min(start.y, current.y),
                width: abs(current.x - start.x), height: abs(current.y - start.y))),
                with: .color(color), lineWidth: style.strokeWidth)
        case .ellipse:
            context.stroke(Path(ellipseIn: CGRect(x: min(start.x, current.x), y: min(start.y, current.y),
                width: abs(current.x - start.x), height: abs(current.y - start.y))),
                with: .color(color), lineWidth: style.strokeWidth)
        case .pen:
            var p = Path()
            if let first = penPoints.first { p.move(to: first); for pt in penPoints.dropFirst() { p.addLine(to: pt) } }
            context.stroke(p, with: .color(color), lineWidth: style.strokeWidth)
        default: break
        }
    }
}
