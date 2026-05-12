import Testing
import Foundation
import CoreGraphics
@testable import Screenshotter

@Test func annotationDocumentAddsAndRemovesElements() {
    var doc = AnnotationDocument(background: nil, size: CGSize(width: 100, height: 100))
    let id = doc.add(.line(start: .zero, end: CGPoint(x: 50, y: 50), style: .defaultStroke))
    #expect(doc.elements.count == 1)
    doc.remove(id: id)
    #expect(doc.elements.isEmpty)
}

@Test func annotationDocumentHitTestsTopElementFirst() {
    var doc = AnnotationDocument(background: nil, size: CGSize(width: 100, height: 100))
    let bottom = doc.add(.rect(frame: CGRect(x: 0, y: 0, width: 100, height: 100), style: .defaultStroke))
    let top = doc.add(.rect(frame: CGRect(x: 10, y: 10, width: 30, height: 30), style: .defaultStroke))
    #expect(doc.hitTest(CGPoint(x: 20, y: 20)) == top)
    #expect(doc.hitTest(CGPoint(x: 80, y: 80)) == bottom)
}
