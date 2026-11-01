//
//  SSE.swift
//  Planly (shared)
//
//  A Server-Sent Events parser for the agent's POST stream. `URLSession.AsyncBytes.lines` drops the
//  blank lines that separate events, so the bytes are split into lines here instead.
//

import Foundation

nonisolated struct SSEEvent: Sendable {
    var event: String
    var data: Data

    func decode<T: Decodable>(_ type: T.Type) -> T? {
        try? PlanlyJSON.decoder().decode(type, from: data)
    }
}

nonisolated struct SSEParser {
    private var event = "message"
    private var dataLines: [String] = []

    /// Feed one line (without its newline). Returns an event when a blank line completes one.
    mutating func feed(_ line: String) -> SSEEvent? {
        if line.isEmpty {
            defer { event = "message"; dataLines = [] }
            guard !dataLines.isEmpty else { return nil }
            return SSEEvent(event: event, data: Data(dataLines.joined(separator: "\n").utf8))
        }
        if line.hasPrefix(":") { return nil } // comment / keep-alive
        if line.hasPrefix("event:") {
            event = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
        } else if line.hasPrefix("data:") {
            var value = line.dropFirst(5)
            if value.first == " " { value = value.dropFirst() }
            dataLines.append(String(value))
        }
        return nil
    }

    /// Turns a byte stream into events.
    static func events(from bytes: URLSession.AsyncBytes) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var parser = SSEParser()
                var line = Data()
                do {
                    for try await byte in bytes {
                        if byte == UInt8(ascii: "\n") {
                            if line.last == UInt8(ascii: "\r") { line.removeLast() }
                            if let event = parser.feed(String(decoding: line, as: UTF8.self)) {
                                continuation.yield(event)
                            }
                            line.removeAll(keepingCapacity: true)
                        } else {
                            line.append(byte)
                        }
                    }
                    if !line.isEmpty, let event = parser.feed(String(decoding: line, as: UTF8.self)) {
                        continuation.yield(event)
                    }
                    if let event = parser.feed("") { continuation.yield(event) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
