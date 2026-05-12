import Foundation
import CoreGraphics

public struct AnnotationDocument: Sendable {
    public let background: CGImage?
    public let size: CGSize
    public private(set) var elements: [Element] = []

    public init(background: CGImage?, size: CGSize) {
        self.background = background
        self.size = size
    }

    @discardableResult
    public mutating func add(_ element: Element) -> UUID {
        elements.append(element)
        return element.id
    }

    @discardableResult
    public mutating func add(_ payload: ElementPayload, style: ElementStyle = .defaultStroke) -> UUID {
        add(Element(payload: payload, style: style))
    }

    public mutating func remove(id: UUID) {
        elements.removeAll { $0.id == id }
    }

    public mutating func update(_ element: Element) {
        if let i = elements.firstIndex(where: { $0.id == element.id }) {
            elements[i] = element
        }
    }

    public func hitTest(_ point: CGPoint) -> UUID? {
        for el in elements.reversed() where el.hitTest(point) {
            return el.id
        }
        return nil
    }
}
