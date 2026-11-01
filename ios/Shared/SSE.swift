import Foundation

/// Server-Sent Events from a POST response (frontend/src/lib/sse.ts).
struct SSEEvent {
    var event: String
    var data: Any
}

enum SSE {
    /// Split complete blocks out of `buffer`; returns parsed events and the unfinished remainder.
    static func parse(_ buffer: String) -> (events: [SSEEvent], rest: String) {
        var blocks = buffer.components(separatedBy: "\n\n")
        let rest = blocks.removeLast()
        var events: [SSEEvent] = []
        for block in blocks {
            var event = "message"
            var data: [String] = []
            for line in block.components(separatedBy: "\n") {
                if line.hasPrefix("event:") {
                    event = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
                } else if line.hasPrefix("data:") {
                    var value = Substring(line.dropFirst(5))
                    while value.first == " " { value = value.dropFirst() }
                    data.append(String(value))
                }
            }
            guard !data.isEmpty,
                  let json = data.joined(separator: "\n").data(using: .utf8),
                  let value = try? JSONSerialization.jsonObject(with: json, options: [.fragmentsAllowed])
            else { continue }
            events.append(SSEEvent(event: event, data: value))
        }
        return (events, rest)
    }

    /// Reads the stream line by line (AsyncBytes.lines drops blank lines, so rebuild the blocks).
    static func events(from bytes: URLSession.AsyncBytes) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            let reader = Task {
                do {
                    var event = "message"
                    var data: [String] = []
                    var buffer = Data()
                    func flush() {
                        defer { event = "message"; data = [] }
                        guard !data.isEmpty, let json = data.joined(separator: "\n").data(using: .utf8),
                              let value = try? JSONSerialization.jsonObject(with: json, options: [.fragmentsAllowed])
                        else { return }
                        continuation.yield(SSEEvent(event: event, data: value))
                    }
                    func handle(_ raw: Data) {
                        var line = String(decoding: raw, as: UTF8.self)
                        if line.hasSuffix("\r") { line.removeLast() }
                        if line.isEmpty { flush() }
                        else if line.hasPrefix("event:") { event = line.dropFirst(6).trimmingCharacters(in: .whitespaces) }
                        else if line.hasPrefix("data:") {
                            var value = Substring(line.dropFirst(5))
                            while value.first == " " { value = value.dropFirst() }
                            data.append(String(value))
                        }
                    }
                    for try await byte in bytes {
                        if byte == UInt8(ascii: "\n") {
                            handle(buffer)
                            buffer.removeAll(keepingCapacity: true)
                        } else {
                            buffer.append(byte)
                        }
                    }
                    if !buffer.isEmpty { handle(buffer) }
                    flush()
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in reader.cancel() }
        }
    }
}
