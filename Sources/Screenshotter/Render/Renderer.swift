import Foundation
import CoreGraphics
import AppKit

public enum RendererError: Error {
    case contextCreationFailed
    case pngEncodeFailed
}

public enum Renderer {
    public static func flatten(_ doc: AnnotationDocument) throws -> Data {
        let width = Int(doc.size.width)
        let height = Int(doc.size.height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw RendererError.contextCreationFailed }

        // Flip so y-down matches AppKit drawing semantics
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)

        // White background fallback
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: doc.size))

        if let bg = doc.background {
            ctx.draw(bg, in: CGRect(origin: .zero, size: doc.size))
        }

        for element in doc.elements {
            draw(element, in: ctx, docSize: doc.size, background: doc.background)
        }

        guard let cg = ctx.makeImage() else { throw RendererError.pngEncodeFailed }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw RendererError.pngEncodeFailed
        }
        return png
    }

    private static func draw(
        _ element: Element,
        in ctx: CGContext,
        docSize: CGSize,
        background: CGImage?
    ) {
        ctx.saveGState()
        ctx.setStrokeColor(element.style.strokeColor)
        ctx.setLineWidth(element.style.strokeWidth)
        if let fill = element.style.fillColor { ctx.setFillColor(fill) }
        switch element.payload {
        case .line(let s, let e):
            ctx.move(to: s)
            ctx.addLine(to: e)
            ctx.strokePath()
        case .rect(let f):
            if element.style.fillColor != nil { ctx.fill(f) }
            ctx.stroke(f)
        case .ellipse(let f):
            if element.style.fillColor != nil { ctx.fillEllipse(in: f) }
            ctx.strokeEllipse(in: f)
        case .text(let f, let content):
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: element.style.fontSize),
                .foregroundColor: NSColor(cgColor: element.style.strokeColor) ?? NSColor.red,
            ]
            let attr = NSAttributedString(string: content, attributes: attrs)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
            attr.draw(in: f)
            NSGraphicsContext.restoreGraphicsState()
        case .pen(_, let points):
            guard let first = points.first else { break }
            ctx.move(to: first)
            for pt in points.dropFirst() { ctx.addLine(to: pt) }
            ctx.strokePath()
        case .blur(let f):
            if let bg = background {
                let bgRect = CGRect(origin: .zero, size: docSize)
                let ci = CIImage(cgImage: bg)
                let blurred = ci.clampedToExtent()
                    .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: element.style.blurRadius])
                    .cropped(to: bgRect)
                let ciCtx = CIContext()
                if let cropped = ciCtx.createCGImage(blurred, from: f.intersection(bgRect)) {
                    ctx.draw(cropped, in: f.intersection(bgRect))
                }
            } else {
                ctx.setFillColor(CGColor(gray: 0.5, alpha: 1))
                ctx.fill(f)
            }
        case .sticker(let f, let id):
            if let image = Stickers.image(for: id) {
                ctx.draw(image, in: f)
            }
        }
        ctx.restoreGState()
    }
}
