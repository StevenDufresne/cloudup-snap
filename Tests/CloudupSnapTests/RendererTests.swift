import Testing
import Foundation
import CoreGraphics
import SnapshotTesting
@testable import CloudupSnap

@Test func rendererProducesNonZeroPNG() throws {
    var doc = AnnotationDocument(background: nil, size: CGSize(width: 100, height: 100))
    doc.add(.rect(frame: CGRect(x: 10, y: 10, width: 80, height: 80), style: .defaultStroke))
    let png = try Renderer.flatten(doc)
    #expect(png.count > 100)
    #expect(png.prefix(8) == Data([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))
}

@Test func rendererSnapshotsBasicShapes() throws {
    var doc = AnnotationDocument(background: nil, size: CGSize(width: 200, height: 200))
    doc.add(.rect(frame: CGRect(x: 20, y: 20, width: 60, height: 60), style: .defaultStroke))
    doc.add(.ellipse(frame: CGRect(x: 100, y: 20, width: 60, height: 60), style: .defaultStroke))
    doc.add(.line(start: CGPoint(x: 20, y: 120), end: CGPoint(x: 180, y: 180), style: .defaultStroke))
    let png = try Renderer.flatten(doc)
    assertSnapshot(of: png, as: .data, named: "basic-shapes")
}
