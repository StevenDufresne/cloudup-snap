import AppKit

/// Native rendering of the Cloudup logo, ported from the source SVG so we don't
/// need to ship asset files. Path data comes from the canonical Cloudup brand
/// SVG (40×40 viewBox); we flip the Y axis at draw time to convert SVG's
/// y-down coordinates to AppKit's y-up.
enum CloudupIcon {
    /// Cloudup brand orange used for the app icon glyph.
    static let brandOrange = NSColor(red: 1.0, green: 119.0/255, blue: 90.0/255, alpha: 1)

    /// Returns the Cloudup glyph as a template `NSImage` at `size` points.
    /// Template images are tinted automatically by the system to match menubar
    /// dark/light themes.
    static func menubarImage(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        let scale = size / 40.0
        let xform = NSAffineTransform()
        xform.translateX(by: 0, yBy: size)
        xform.scaleX(by: scale, yBy: -scale)
        xform.concat()
        NSColor.black.setFill()
        path().fill()
        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    /// Renders the full app icon: a rounded square with the Cloudup glyph
    /// centered in brand orange. Suitable for `NSApp.applicationIconImage`
    /// and for `.icns` generation.
    static func appIconImage(size: CGFloat = 512) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()

        // Rounded-square background (white)
        let cornerRadius = size * 0.225  // matches modern macOS icon corner-ish
        let bgRect = NSRect(origin: .zero, size: image.size)
        let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: cornerRadius, yRadius: cornerRadius)
        NSColor.white.setFill()
        bgPath.fill()

        // Cloudup glyph centered, 70% of icon size, in brand orange.
        let glyphSize = size * 0.7
        let glyphOriginX = (size - glyphSize) / 2
        let glyphOriginY = (size - glyphSize) / 2
        let glyphScale = glyphSize / 40.0
        let xform = NSAffineTransform()
        xform.translateX(by: glyphOriginX, yBy: glyphOriginY + glyphSize)
        xform.scaleX(by: glyphScale, yBy: -glyphScale)
        xform.concat()
        brandOrange.setFill()
        path().fill()

        image.unlockFocus()
        return image
    }

    /// The Cloudup logo as an NSBezierPath in the SVG's 40×40 coordinate space.
    static func path() -> NSBezierPath {
        let p = NSBezierPath()
        p.windingRule = .evenOdd

        // ── Outer circle ──
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

        // ── Inner cloud + bite (rendered as a hole via even-odd fill) ──
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
}
