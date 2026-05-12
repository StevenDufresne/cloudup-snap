import AppKit
import Foundation

public struct ClipboardService {
    public init() {}
    public func copy(_ url: URL) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(url.absoluteString, forType: .string)
    }
}
