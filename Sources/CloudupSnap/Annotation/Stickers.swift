import Foundation
import AppKit
import CoreGraphics

public enum Stickers {
    /// Built-in sticker IDs. Three groups: 80 emoji, 8 arrows, 9 numbered pins.
    public static let allIDs: [String] = (1...80).map { "emoji-\($0)" }
        + (0...7).map { "arrow-\($0)" }
        + (1...9).map { "pin-\($0)" }

    public static func image(for id: String) -> CGImage? {
        if id.hasPrefix("emoji-") {
            let n = Int(id.dropFirst("emoji-".count)) ?? 1
            return renderText(emojiChar(n), size: 64)
        }
        if id.hasPrefix("arrow-") {
            let n = Int(id.dropFirst("arrow-".count)) ?? 0
            let names = ["arrow.up", "arrow.up.right", "arrow.right", "arrow.down.right",
                         "arrow.down", "arrow.down.left", "arrow.left", "arrow.up.left"]
            return renderSymbol(names[n % 8], size: 64)
        }
        if id.hasPrefix("pin-") {
            let n = Int(id.dropFirst("pin-".count)) ?? 1
            return renderSymbol("\(n).circle.fill", size: 64)
        }
        return nil
    }

    private static func emojiChar(_ n: Int) -> String {
        // First 40 entries are kept stable — existing documents reference them
        // by index. New entries are appended after.
        let pool = ["😀", "😂", "🤔", "🙃", "😎", "🤩", "😇", "🥳", "🤯", "😅",
                    "🔥", "💥", "✨", "🎉", "💯", "👀", "👉", "👈", "✅", "❌",
                    "❤️", "💔", "⭐️", "⚠️", "🚨", "💡", "🔒", "🔑", "📌", "📎",
                    "🎯", "🏆", "🎁", "🎵", "☕️", "🍕", "🐶", "🐱", "🐢", "🦄",
                    "😭", "😴", "😡", "😱", "🤗", "😉", "😘", "🥰", "😋", "🤪",
                    "👍", "👎", "👏", "🙌", "🙏", "👋", "🤝", "☝️", "👇", "✋",
                    "❓", "❗️", "🔔", "💎", "💰", "📈", "📉", "🚀", "🐛", "🧠",
                    "🤖", "📝", "✏️", "📷", "🎨", "💬", "🐰", "🐼", "🦊", "🦁"]
        return pool[(n - 1) % pool.count]
    }

    private static func renderText(_ text: String, size: CGFloat) -> CGImage? {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size * 0.85)]
        (text as NSString).draw(at: NSPoint(x: size * 0.07, y: size * 0.05), withAttributes: attrs)
        image.unlockFocus()
        var rect = NSRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    private static func renderSymbol(_ name: String, size: CGFloat) -> CGImage? {
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        let config = NSImage.SymbolConfiguration(pointSize: size * 0.85, weight: .bold)
            .applying(.init(paletteColors: [.systemRed]))
        let resized = symbol.withSymbolConfiguration(config) ?? symbol
        var rect = NSRect(origin: .zero, size: NSSize(width: size, height: size))
        return resized.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}
