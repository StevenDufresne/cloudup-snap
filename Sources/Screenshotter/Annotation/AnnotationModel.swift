import Foundation
import CoreGraphics

public struct ElementStyle: Equatable, Sendable {
    public var strokeColor: CGColor
    public var strokeWidth: CGFloat
    public var fillColor: CGColor?
    public var fontSize: CGFloat
    public var blurRadius: CGFloat

    public static let defaultStroke = ElementStyle(
        strokeColor: CGColor(red: 1, green: 0, blue: 0, alpha: 1),
        strokeWidth: 3,
        fillColor: nil,
        fontSize: 16,
        blurRadius: 12
    )
}

public enum ElementPayload: Equatable, Sendable {
    case line(start: CGPoint, end: CGPoint)
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
        case .line(let s, let e):
            return CGRect(x: min(s.x, e.x), y: min(s.y, e.y),
                          width: abs(e.x - s.x), height: abs(e.y - s.y)).insetBy(dx: -8, dy: -8)
        case .rect(let f), .ellipse(let f), .text(let f, _), .pen(let f, _), .blur(let f), .sticker(let f, _):
            return f
        }
    }

    public func hitTest(_ p: CGPoint) -> Bool { frame.contains(p) }
}

public extension Element {
    static func line(start: CGPoint, end: CGPoint, style: ElementStyle) -> Element {
        Element(payload: .line(start: start, end: end), style: style)
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
