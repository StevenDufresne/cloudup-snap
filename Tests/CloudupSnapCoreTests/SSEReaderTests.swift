import Testing
import Foundation
@testable import CloudupSnapCore

@Test func sseReaderParsesSingleDataEvent() async throws {
    let stream = AsyncStream<Data> { cont in
        cont.yield("data: {\"hello\":\"world\"}\n\n".data(using: .utf8)!)
        cont.finish()
    }
    var events: [SSEEvent] = []
    for try await event in SSEReader(byteStream: stream).events {
        events.append(event)
    }
    #expect(events.count == 1)
    #expect(events[0].data == "{\"hello\":\"world\"}")
}

@Test func sseReaderHandlesMultilineData() async throws {
    let payload = "data: line1\ndata: line2\n\n"
    let stream = AsyncStream<Data> { cont in
        cont.yield(payload.data(using: .utf8)!)
        cont.finish()
    }
    var events: [SSEEvent] = []
    for try await event in SSEReader(byteStream: stream).events { events.append(event) }
    #expect(events.count == 1)
    #expect(events[0].data == "line1\nline2")
}

@Test func sseReaderHandlesChunkedDelivery() async throws {
    let stream = AsyncStream<Data> { cont in
        cont.yield("data: hel".data(using: .utf8)!)
        cont.yield("lo\n\n".data(using: .utf8)!)
        cont.finish()
    }
    var events: [SSEEvent] = []
    for try await event in SSEReader(byteStream: stream).events { events.append(event) }
    #expect(events.count == 1)
    #expect(events[0].data == "hello")
}

@Test func sseReaderIgnoresComments() async throws {
    let stream = AsyncStream<Data> { cont in
        cont.yield(": heartbeat\n\ndata: x\n\n".data(using: .utf8)!)
        cont.finish()
    }
    var events: [SSEEvent] = []
    for try await event in SSEReader(byteStream: stream).events { events.append(event) }
    #expect(events.count == 1)
    #expect(events[0].data == "x")
}
