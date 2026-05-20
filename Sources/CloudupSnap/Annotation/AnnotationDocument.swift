import Foundation
import CoreGraphics

public struct AnnotationDocument: Sendable {
    public let background: CGImage?
    /// Logical (point) size. Used for the editor canvas, gesture coordinates,
    /// and the AnnotationModel's element positions.
    public let size: CGSize
    /// Pixel-density factor — `background` is `size * pixelScale` pixels.
    /// Used by the Renderer to produce a high-resolution final PNG.
    public let pixelScale: CGFloat
    public private(set) var elements: [Element] = []

    public init(background: CGImage?, size: CGSize, pixelScale: CGFloat = 1.0) {
        self.background = background
        self.size = size
        self.pixelScale = pixelScale
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
