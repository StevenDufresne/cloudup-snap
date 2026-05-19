import Foundation
import CoreGraphics

public struct ElementStyle: Equatable, Sendable {
    public var strokeColor: CGColor
    public var strokeWidth: CGFloat
    public var fillColor: CGColor?
    public var fontSize: CGFloat
    public var blurRadius: CGFloat
    public var isDashed: Bool

    public init(
        strokeColor: CGColor,
        strokeWidth: CGFloat,
        fillColor: CGColor? = nil,
        fontSize: CGFloat = 16,
        blurRadius: CGFloat = 12,
        isDashed: Bool = false
    ) {
        self.strokeColor = strokeColor
        self.strokeWidth = strokeWidth
        self.fillColor = fillColor
        self.fontSize = fontSize
        self.blurRadius = blurRadius
        self.isDashed = isDashed
    }

    /// Dash pattern derived from the current stroke width — wider strokes get
    /// proportionally wider dashes so the dotted look stays balanced.
    public var dashLengths: [CGFloat] {
        let unit = max(2, strokeWidth * 2)
        return [unit, unit]
    }

    /// Cloudup brand orange (#ff775a)
    public static let defaultStroke = ElementStyle(
        strokeColor: CGColor(red: 1.0, green: 119.0/255, blue: 90.0/255, alpha: 1),
        strokeWidth: 3,
        fillColor: nil,
        fontSize: 16,
        blurRadius: 12,
        isDashed: false
    )
}

public enum ElementPayload: Equatable, Sendable {
    case line(start: CGPoint, end: CGPoint)
    case arrow(start: CGPoint, end: CGPoint)
    case rect(frame: CGRect)
    case ellipse(frame: CGRect)
    case text(frame: CGRect, content: String)
    case pen(frame: CGRect, points: [CGPoint])
    case blur(frame: CGRect)
    case sticker(frame: CGRect, id: String)
}

public struct Element: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var payload: ElementPayload
    public var style: ElementStyle

    public init(payload: ElementPayload, style: ElementStyle = .defaultStroke) {
        self.id = UUID()
        self.payload = payload
        self.style = style
    }

    public var frame: CGRect {
        switch payload {
        case .line(let s, let e), .arrow(let s, let e):
            return CGRect(x: min(s.x, e.x), y: min(s.y, e.y),
                          width: abs(e.x - s.x), height: abs(e.y - s.y)).insetBy(dx: -8, dy: -8)
        case .rect(let f), .ellipse(let f), .text(let f, _), .pen(let f, _), .blur(let f), .sticker(let f, _):
            return f
        }
    }

    public func hitTest(_ p: CGPoint) -> Bool { frame.contains(p) }

    /// Returns a copy of this element translated by `delta` (in points).
    public func translated(by delta: CGVector) -> Element {
        var out = self
        switch payload {
        case .line(let s, let e):
            out.payload = .line(
                start: CGPoint(x: s.x + delta.dx, y: s.y + delta.dy),
                end:   CGPoint(x: e.x + delta.dx, y: e.y + delta.dy))
        case .arrow(let s, let e):
            out.payload = .arrow(
                start: CGPoint(x: s.x + delta.dx, y: s.y + delta.dy),
                end:   CGPoint(x: e.x + delta.dx, y: e.y + delta.dy))
        case .rect(let f):    out.payload = .rect(frame: f.offsetBy(dx: delta.dx, dy: delta.dy))
        case .ellipse(let f): out.payload = .ellipse(frame: f.offsetBy(dx: delta.dx, dy: delta.dy))
        case .text(let f, let c):
            out.payload = .text(frame: f.offsetBy(dx: delta.dx, dy: delta.dy), content: c)
        case .pen(let f, let points):
            let np = points.map { CGPoint(x: $0.x + delta.dx, y: $0.y + delta.dy) }
            out.payload = .pen(frame: f.offsetBy(dx: delta.dx, dy: delta.dy), points: np)
        case .blur(let f):    out.payload = .blur(frame: f.offsetBy(dx: delta.dx, dy: delta.dy))
        case .sticker(let f, let id):
            out.payload = .sticker(frame: f.offsetBy(dx: delta.dx, dy: delta.dy), id: id)
        }
        return out
    }
}

public extension Element {
    static func line(start: CGPoint, end: CGPoint, style: ElementStyle) -> Element {
        Element(payload: .line(start: start, end: end), style: style)
    }
    static func arrow(start: CGPoint, end: CGPoint, style: ElementStyle) -> Element {
        Element(payload: .arrow(start: start, end: end), style: style)
    }
    static func rect(frame: CGRect, style: ElementStyle) -> Element {
        Element(payload: .rect(frame: frame), style: style)
    }
    static func ellipse(frame: CGRect, style: ElementStyle) -> Element {
        Element(payload: .ellipse(frame: frame), style: style)
    }
    static func text(frame: CGRect, content: String, style: ElementStyle) -> Element {
        Element(payload: .text(frame: frame, content: content), style: style)
    }
    static func pen(frame: CGRect, points: [CGPoint], style: ElementStyle) -> Element {
        Element(payload: .pen(frame: frame, points: points), style: style)
    }
    static func blur(frame: CGRect, style: ElementStyle = .defaultStroke) -> Element {
        Element(payload: .blur(frame: frame), style: style)
    }
    static func sticker(frame: CGRect, id: String) -> Element {
        Element(payload: .sticker(frame: frame, id: id), style: .defaultStroke)
    }
}
