// Renders the Cloudup app icon at all required sizes into an .iconset
// directory. Driven by tools/gen-icon.sh, which then invokes `iconutil`
// to produce the final AppIcon.icns.
//
// Usage: swift tools/gen-icon.swift <output-iconset-dir>
//
// The Cloudup path data is duplicated here (mirror of
// Sources/CloudupSnap/Menubar/CloudupIcon.swift) so this script can run
// as a standalone Swift one-shot without depending on the app target.

import AppKit
import Foundation

let brandOrange = NSColor(red: 1.0, green: 119.0/255, blue: 90.0/255, alpha: 1)

func cloudupPath() -> NSBezierPath {
    let p = NSBezierPath()
    p.windingRule = .evenOdd

    // Outer circle
    p.move(to: NSPoint(x: 19.5255, y: 0.260742))
    p.curve(to: NSPoint(x: 0, y: 19.7863),
            controlPoint1: NSPoint(x: 8.74091, y: 0.260742),
            controlPoint2: NSPoint(x: 0, y: 9.00335))
    p.curve(to: NSPoint(x: 19.5255, y: 39.3118),
            controlPoint1: NSPoint(x: 0, y: 30.5692),
            controlPoint2: NSPoint(x: 8.74261, y: 39.3118))
    p.curve(to: NSPoint(x: 39.0511, y: 19.7863),
            controlPoint1: NSPoint(x: 30.3085, y: 39.3118),
            controlPoint2: NSPoint(x: 39.0511, y: 30.5692))
    p.curve(to: NSPoint(x: 19.5255, y: 0.260742),
            controlPoint1: NSPoint(x: 39.0511, y: 9.00335),
            controlPoint2: NSPoint(x: 30.3102, y: 0.260742))
    p.close()

    // Inner cloud + bite
    p.move(to: NSPoint(x: 19.49, y: 35.8023))
    p.curve(to: NSPoint(x: 3.474, y: 19.7863),
            controlPoint1: NSPoint(x: 10.644, y: 35.8023),
            controlPoint2: NSPoint(x: 3.474, y: 28.6323))
    p.curve(to: NSPoint(x: 19.49, y: 3.77032),
            controlPoint1: NSPoint(x: 3.474, y: 10.9403),
            controlPoint2: NSPoint(x: 10.644, y: 3.77032))
    p.curve(to: NSPoint(x: 34.9619, y: 15.6378),
            controlPoint1: NSPoint(x: 26.9006, y: 3.77032),
            controlPoint2: NSPoint(x: 33.1351, y: 8.80338))
    p.curve(to: NSPoint(x: 34.7552, y: 15.9056),
            controlPoint1: NSPoint(x: 34.8908, y: 15.726),
            controlPoint2: NSPoint(x: 34.8213, y: 15.8141))
    p.curve(to: NSPoint(x: 29.9628, y: 18.4001),
            controlPoint1: NSPoint(x: 33.6334, y: 17.4494),
            controlPoint2: NSPoint(x: 31.8709, y: 18.4001))
    p.line(to: NSPoint(x: 29.634, y: 18.4001))
    p.curve(to: NSPoint(x: 24.8416, y: 15.9056),
            controlPoint1: NSPoint(x: 27.7259, y: 18.4001),
            controlPoint2: NSPoint(x: 25.9635, y: 17.4511))
    p.curve(to: NSPoint(x: 19.1476, y: 13.184),
            controlPoint1: NSPoint(x: 23.5791, y: 14.1652),
            controlPoint2: NSPoint(x: 21.4879, y: 13.0654))
    p.curve(to: NSPoint(x: 12.8961, y: 19.3084),
            controlPoint1: NSPoint(x: 15.838, y: 13.3501),
            controlPoint2: NSPoint(x: 13.1283, y: 16.0039))
    p.curve(to: NSPoint(x: 19.49, y: 26.3954),
            controlPoint1: NSPoint(x: 12.625, y: 23.1756),
            controlPoint2: NSPoint(x: 15.6804, y: 26.3954))
    p.curve(to: NSPoint(x: 24.8535, y: 23.6484),
            controlPoint1: NSPoint(x: 21.6981, y: 26.3954),
            controlPoint2: NSPoint(x: 23.652, y: 25.3125))
    p.curve(to: NSPoint(x: 29.634, y: 21.1708),
            controlPoint1: NSPoint(x: 25.9668, y: 22.1062),
            controlPoint2: NSPoint(x: 27.7326, y: 21.1708))
    p.line(to: NSPoint(x: 29.9645, y: 21.1708))
    p.curve(to: NSPoint(x: 34.745, y: 23.6484),
            controlPoint1: NSPoint(x: 31.8659, y: 21.1708),
            controlPoint2: NSPoint(x: 33.6317, y: 22.1062))
    p.curve(to: NSPoint(x: 34.9636, y: 23.9331),
            controlPoint1: NSPoint(x: 34.8145, y: 23.7449),
            controlPoint2: NSPoint(x: 34.8874, y: 23.8399))
    p.curve(to: NSPoint(x: 19.4917, y: 35.8006),
            controlPoint1: NSPoint(x: 33.1351, y: 30.7675),
            controlPoint2: NSPoint(x: 26.9023, y: 35.8006))
    p.line(to: NSPoint(x: 19.49, y: 35.8023))
    p.close()

    return p
}

func renderIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let cornerRadius = size * 0.225
    let bgRect = NSRect(origin: .zero, size: image.size)
    let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: cornerRadius, yRadius: cornerRadius)
    NSColor.white.setFill()
    bgPath.fill()

    let glyphSize = size * 0.7
    let glyphOriginX = (size - glyphSize) / 2
    let glyphOriginY = (size - glyphSize) / 2
    let glyphScale = glyphSize / 40.0
    let xform = NSAffineTransform()
    xform.translateX(by: glyphOriginX, yBy: glyphOriginY + glyphSize)
    xform.scaleX(by: glyphScale, yBy: -glyphScale)
    xform.concat()
    brandOrange.setFill()
    cloudupPath().fill()

    image.unlockFocus()
    return image
}

func writePNG(_ image: NSImage, to path: String) throws {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "gen-icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "PNG encode failed"])
    }
    try data.write(to: URL(fileURLWithPath: path))
}

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write("usage: gen-icon.swift <iconset-dir>\n".data(using: .utf8)!)
    exit(2)
}
let iconsetDir = args[1]
try? FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

let entries: [(name: String, size: CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for entry in entries {
    let img = renderIcon(size: entry.size)
    let path = "\(iconsetDir)/\(entry.name)"
    try writePNG(img, to: path)
    print("wrote \(entry.name) (\(Int(entry.size))×\(Int(entry.size)))")
}
