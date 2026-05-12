import Foundation

public struct SSEEvent: Equatable, Sendable {
    public let event: String
    public let data: String
    public let id: String?
}

public struct SSEReader: Sendable {
    private let byteStream: AsyncStream<Data>
    public init(byteStream: AsyncStream<Data>) { self.byteStream = byteStream }

    public var events: AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var buffer = ""
                var pendingData: [String] = []
                var pendingEvent: String = "message"
                var pendingId: String? = nil

                func flushIfReady() {
                    if !pendingData.isEmpty {
                        let event = SSEEvent(
                            event: pendingEvent,
                            data: pendingData.joined(separator: "\n"),
                            id: pendingId
                        )
                        continuation.yield(event)
                        pendingData.removeAll()
                        pendingEvent = "message"
                    }
                }

                for await chunk in byteStream {
                    if let s = String(data: chunk, encoding: .utf8) {
                        buffer.append(s)
                    }
                    while let nl = buffer.firstIndex(of: "\n") {
                        let line = String(buffer[..<nl])
                        buffer.removeSubrange(buffer.startIndex...nl)
                        if line.isEmpty {
                            flushIfReady()
                        } else if line.hasPrefix(":") {
                            continue
                        } else if line.hasPrefix("data:") {
                            let payload = line.dropFirst("data:".count).drop { $0 == " " }
                            pendingData.append(String(payload))
                        } else if line.hasPrefix("event:") {
                            pendingEvent = String(line.dropFirst("event:".count).drop { $0 == " " })
                        } else if line.hasPrefix("id:") {
                            pendingId = String(line.dropFirst("id:".count).drop { $0 == " " })
                        }
                    }
                }
                flushIfReady()
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
