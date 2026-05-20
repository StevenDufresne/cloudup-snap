import Testing
import Foundation
import CoreGraphics
@testable import CloudupSnap

@Test func undoStackRoundTripsAdd() {
    var doc = AnnotationDocument(background: nil, size: CGSize(width: 100, height: 100))
    var stack = UndoStack()
    let element = Element.rect(frame: CGRect(x: 0, y: 0, width: 10, height: 10), style: .defaultStroke)
    stack.perform(.add(element), on: &doc)
    #expect(doc.elements.count == 1)
    stack.undo(on: &doc)
    #expect(doc.elements.isEmpty)
    stack.redo(on: &doc)
    #expect(doc.elements.count == 1)
}

@Test func undoStackCapsAt50() {
    var doc = AnnotationDocument(background: nil, size: CGSize(width: 100, height: 100))
    var stack = UndoStack(capacity: 50)
    for i in 0..<60 {
        let e = Element.rect(frame: CGRect(x: CGFloat(i), y: 0, width: 10, height: 10), style: .defaultStroke)
        stack.perform(.add(e), on: &doc)
    }
    #expect(stack.undoDepth == 50)
}
