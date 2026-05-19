import Foundation

public struct HistoryEntry: Codable, Equatable, Sendable {
    public let url: String
    public let timestamp: Date
    public let txHash: String?
    public let costUSDC: Decimal?
    public let originalFilename: String?

    public init(url: String, timestamp: Date = Date(), txHash: String? = nil,
                costUSDC: Decimal? = nil, originalFilename: String? = nil) {
        self.url = url
        self.timestamp = timestamp
        self.txHash = txHash
        self.costUSDC = costUSDC
        self.originalFilename = originalFilename
    }

    /// Compact label suitable for a menubar menu item.
    /// E.g. "Today 11:32 — /s/chn0…iutDmoo" or "May 12 — /s/abc…xyz".
    public func menuLabel() -> String {
        let f = DateFormatter()
        if Calendar.current.isDateInToday(timestamp) {
            f.dateFormat = "'Today' HH:mm"
        } else if Calendar.current.isDateInYesterday(timestamp) {
            f.dateFormat = "'Yesterday' HH:mm"
        } else {
            f.dateFormat = "MMM d HH:mm"
        }
        let dateStr = f.string(from: timestamp)
        let shortPath: String = {
            if let parsed = URL(string: url) {
                let path = parsed.path
                if path.count > 32 {
                    let head = path.prefix(20)
                    let tail = path.suffix(10)
                    return "\(head)…\(tail)"
                }
                return path
            }
            return url
        }()
        return "\(dateStr) — \(shortPath)"
    }
}

/// JSON-on-disk history of upload URLs, capped at `capacity`. Most-recent
/// first (entries are prepended on `append`).
public actor HistoryStore {
    public static let shared = HistoryStore()

    public let capacity: Int
    private let path: URL
    private var entries: [HistoryEntry] = []
    private var loaded = false

    public init(capacity: Int = 50,
                directory: URL? = nil) {
        self.capacity = capacity
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory,
                                                          in: .userDomainMask).first!
            .appendingPathComponent("Screenshotter", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        self.path = base.appendingPathComponent("history.json")
    }

    public func recent(limit: Int) -> [HistoryEntry] {
        loadIfNeeded()
        return Array(entries.prefix(limit))
    }

    public func append(_ entry: HistoryEntry) {
        loadIfNeeded()
        entries.insert(entry, at: 0)
        if entries.count > capacity {
            entries.removeLast(entries.count - capacity)
        }
        save()
    }

    public func clear() {
        entries.removeAll()
        save()
    }

    // MARK: -

    private func loadIfNeeded() {
        if loaded { return }
        loaded = true
        guard let data = try? Data(contentsOf: path) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([HistoryEntry].self, from: data) {
            entries = decoded
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(entries) {
            try? data.write(to: path, options: .atomic)
        }
    }
}
