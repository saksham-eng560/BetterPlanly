//
//  APIClient.swift
//  Planly (shared)
//
//  A client for the same HTTP API the website uses (docs/API.md). All paths live under `/api`.
//

import Foundation

nonisolated struct APIError: LocalizedError, Sendable {
    var status: Int
    var detail: String
    var errors: [String] = []

    var errorDescription: String? { detail }
}

nonisolated extension Error {
    /// True when the Mac couldn't be reached at all (as opposed to the server answering with an error).
    var isOffline: Bool {
        guard let urlError = self as? URLError else { return false }
        switch urlError.code {
        case .notConnectedToInternet, .cannotConnectToHost, .cannotFindHost, .timedOut,
             .networkConnectionLost, .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed,
             .secureConnectionFailed:
            return true
        default:
            return false
        }
    }

    /// The text to show the person: the server's `detail`, or a friendly line for network failures.
    var userMessage: String {
        if let api = self as? APIError { return api.detail }
        if isOffline { return "Can't reach Planly on your Mac." }
        return localizedDescription
    }
}

nonisolated struct APIClient: Sendable {
    /// The server root, e.g. http://My-MacBook.local:8000 (without `/api`).
    let server: URL

    init(server: URL) { self.server = server }

    init?(address: String) {
        guard let normalized = Self.normalize(address), let url = URL(string: normalized) else { return nil }
        server = url
    }

    /// Accepts what people type ("my-mac.local", "192.168.1.20:8080/api/") and returns
    /// "http://my-mac.local:8000": adds http://, defaults the port to 8000, strips a trailing / or /api.
    static func normalize(_ input: String) -> String? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "http://" + text }
        while text.hasSuffix("/") { text.removeLast() }
        if text.lowercased().hasSuffix("/api") { text.removeLast(4) }
        while text.hasSuffix("/") { text.removeLast() }
        guard var components = URLComponents(string: text), let host = components.host, !host.isEmpty else { return nil }
        if components.port == nil { components.port = 8000 }
        return components.string
    }

    // MARK: Plumbing

    private func url(_ path: String, _ query: [URLQueryItem] = []) -> URL {
        var components = URLComponents(url: server.appendingPathComponent("api" + path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        return components.url!
    }

    private func makeRequest(_ method: String, _ path: String, query: [URLQueryItem] = [],
                             body: [String: JSONValue]? = nil, timeout: TimeInterval = 15) throws -> URLRequest {
        var request = URLRequest(url: url(path, query), timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        return request
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.check(response, data)
        return data
    }

    private static func check(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard !(200..<300).contains(http.statusCode) else { return }
        throw apiError(status: http.statusCode, data: data)
    }

    private static func apiError(status: Int, data: Data) -> APIError {
        struct Body: Decodable { var detail: Detail?; var errors: [String]? }
        enum Detail: Decodable {
            case text(String), other
            init(from decoder: Decoder) throws {
                self = (try? decoder.singleValueContainer().decode(String.self)).map(Detail.text) ?? .other
            }
        }
        let body = try? JSONDecoder().decode(Body.self, from: data)
        var detail = HTTPURLResponse.localizedString(forStatusCode: status).capitalized
        if case .text(let text)? = body?.detail { detail = text }
        return APIError(status: status, detail: detail, errors: body?.errors ?? [])
    }

    private func call<T: Decodable>(_ method: String, _ path: String, query: [URLQueryItem] = [],
                                    body: [String: JSONValue]? = nil) async throws -> T {
        let data = try await send(makeRequest(method, path, query: query, body: body))
        return try PlanlyJSON.decoder().decode(T.self, from: data)
    }

    // MARK: Endpoints

    func health() async throws -> Bool {
        struct Health: Decodable { var ok: Bool }
        let request = try makeRequest("GET", "/health", timeout: 5)
        let data = try await send(request)
        return (try? JSONDecoder().decode(Health.self, from: data).ok) ?? true
    }

    func tasks(start: String, end: String) async throws -> [PlanTask] {
        try await call("GET", "/tasks", query: [.init(name: "start", value: start), .init(name: "end", value: end)])
    }

    func missed(before: String) async throws -> [PlanTask] {
        try await call("GET", "/tasks", query: [.init(name: "missed_before", value: before)])
    }

    func unscheduled() async throws -> [PlanTask] {
        try await call("GET", "/tasks", query: [.init(name: "unscheduled", value: "true")])
    }

    func task(_ id: Int) async throws -> PlanTask {
        try await call("GET", "/tasks/\(id)")
    }

    func createTask(_ fields: [String: JSONValue]) async throws -> TaskChange {
        try await call("POST", "/tasks", body: fields)
    }

    func updateTask(_ id: Int, _ fields: [String: JSONValue]) async throws -> TaskChange {
        try await call("PATCH", "/tasks/\(id)", body: fields)
    }

    func deleteTask(_ id: Int) async throws -> TaskChange {
        try await call("DELETE", "/tasks/\(id)")
    }

    func complete(_ id: Int) async throws -> TaskChange {
        try await call("POST", "/tasks/\(id)/complete")
    }

    func uncomplete(_ id: Int) async throws -> TaskChange {
        try await call("POST", "/tasks/\(id)/uncomplete")
    }

    func reschedule(_ id: Int, to date: String?, keepTime: Bool = true) async throws -> TaskChange {
        try await call("POST", "/tasks/\(id)/reschedule", body: ["date": JSONValue(date), "keep_time": .bool(keepTime)])
    }

    func setChecklist(_ itemId: Int, done: Bool) async throws -> TaskChange {
        try await call("PATCH", "/checklist/\(itemId)", body: ["done": .bool(done)])
    }

    func history(limit: Int = 50) async throws -> [ChangeSet] {
        try await call("GET", "/history", query: [.init(name: "limit", value: String(limit))])
    }

    func undo(_ changeSetId: Int) async throws -> ChangeSet {
        try await call("POST", "/history/\(changeSetId)/undo")
    }

    /// Uploads files as one multipart request (repeated `files` field); imported as one change set.
    func importFiles(_ files: [(name: String, data: Data)]) async throws -> ImportResult {
        let boundary = "planly-\(UUID().uuidString)"
        var body = Data()
        for file in files {
            let name = file.name.replacingOccurrences(of: "\"", with: "")
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"files\"; filename=\"\(name)\"\r\n".utf8))
            body.append(Data("Content-Type: application/octet-stream\r\n\r\n".utf8))
            body.append(file.data)
            body.append(Data("\r\n".utf8))
        }
        body.append(Data("--\(boundary)--\r\n".utf8))

        var request = try makeRequest("POST", "/imports/file", timeout: 120)
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return try PlanlyJSON.decoder().decode(ImportResult.self, from: try await send(request))
    }

    func importNotion(databaseId: String) async throws -> ImportResult {
        let request = try makeRequest("POST", "/imports/notion", body: ["database_id": .string(databaseId)], timeout: 120)
        return try PlanlyJSON.decoder().decode(ImportResult.self, from: try await send(request))
    }

    /// The plan export as a JSON file, written to a temporary URL ready for the share sheet.
    func export() async throws -> URL {
        let request = try makeRequest("GET", "/export", timeout: 60)
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.check(response, data)
        var filename = "planly-export-\(PlanDates.today()).json"
        if let disposition = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition"),
           let range = disposition.range(of: "filename=") {
            filename = disposition[range.upperBound...].trimmingCharacters(in: CharacterSet(charactersIn: "\"; "))
        }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: file, options: .atomic)
        return file
    }

    func state(today: String) async throws -> AppState {
        try await call("GET", "/state", query: [.init(name: "today", value: today)])
    }

    func thread() async throws -> AgentThread {
        try await call("GET", "/agent/thread")
    }

    /// Starts an agent run and returns its event stream. Throws `APIError` with status 409 when a
    /// run is already active.
    func agentRun(_ body: [String: JSONValue]) async throws -> AsyncThrowingStream<SSEEvent, Error> {
        var request = try makeRequest("POST", "/agent/runs", body: body, timeout: 600)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            var data = Data()
            for try await byte in bytes { data.append(byte) }
            throw Self.apiError(status: http.statusCode, data: data)
        }
        return SSEParser.events(from: bytes)
    }
}
