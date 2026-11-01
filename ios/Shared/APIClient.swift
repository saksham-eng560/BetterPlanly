import Foundation

/// An error the user can read; the server's `detail` when it sent one.
struct APIError: LocalizedError {
    var status: Int
    var message: String
    var errors: [String] = []

    var errorDescription: String? {
        errors.isEmpty ? message : ([message] + errors.prefix(5)).joined(separator: "\n")
    }

    static let notConfigured = APIError(status: 0, message: "Add your Mac's address in Settings first.")
}

/// Typed client for the Planly backend (docs/API.md), the Swift twin of frontend/src/lib/api.ts.
struct APIClient {
    var baseURL: String

    init(baseURL: String = SharedStore.serverURL) {
        self.baseURL = baseURL
    }

    static var shared: APIClient { APIClient() }

    /// Short timeouts: on the wrong Wi-Fi the app should say so quickly, not spin.
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    /// Agent runs stream for minutes on a slow model.
    static let streamingSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 900
        return URLSession(configuration: config)
    }()

    func url(_ path: String) throws -> URL {
        guard let url = URL(string: baseURL + "/api" + path), url.host != nil else { throw APIError.notConfigured }
        return url
    }

    func request(_ method: String, _ path: String, json: Data? = nil) throws -> URLRequest {
        var request = URLRequest(url: try url(path))
        request.httpMethod = method
        if let json {
            request.httpBody = json
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data, response: URLResponse
        do {
            (data, response) = try await Self.session.data(for: request)
        } catch let error as URLError {
            throw APIError(status: 0, message: Self.describe(error))
        }
        try Self.check(response, data)
        do {
            return try JSONDecoder.planly.decode(T.self, from: data)
        } catch {
            throw APIError(status: 0, message: "The server sent something unexpected (\(error.localizedDescription)).")
        }
    }

    static func check(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard !(200..<300).contains(http.statusCode) else { return }
        var message = HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
        var errors: [String] = []
        if let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let detail = body["detail"] as? String { message = detail }
            else if let detail = body["detail"] { message = String(describing: detail) }
            errors = body["errors"] as? [String] ?? []
        }
        throw APIError(status: http.statusCode, message: message, errors: errors)
    }

    static func describe(_ error: URLError) -> String {
        switch error.code {
        case .timedOut, .cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .notConnectedToInternet, .dnsLookupFailed:
            "Can't reach Planly on your Mac. Check that it's running with `make phone` and that this iPhone is on the same Wi-Fi."
        default:
            error.localizedDescription
        }
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        try await send(request("GET", path))
    }

    private func post<T: Decodable>(_ path: String, _ body: [String: Any]? = nil) async throws -> T {
        let json = try body.map { try JSONSerialization.data(withJSONObject: $0) }
        return try await send(request("POST", path, json: json))
    }

    // MARK: endpoints

    func health() async throws -> Bool {
        struct Health: Decodable { var ok: Bool }
        let health: Health = try await get("/health")
        return health.ok
    }

    func tasks(start: String, end: String) async throws -> [PlanTask] { try await get("/tasks?start=\(start)&end=\(end)") }
    func missed(before: String) async throws -> [PlanTask] { try await get("/tasks?missed_before=\(before)") }
    func unscheduled() async throws -> [PlanTask] { try await get("/tasks?unscheduled=true") }
    func task(_ id: Int) async throws -> PlanTask { try await get("/tasks/\(id)") }

    func createTask(_ task: NewTask) async throws -> TaskChange {
        try await send(request("POST", "/tasks", json: try JSONEncoder.planly.encode(task)))
    }

    func complete(_ id: Int) async throws -> TaskChange { try await post("/tasks/\(id)/complete") }
    func uncomplete(_ id: Int) async throws -> TaskChange { try await post("/tasks/\(id)/uncomplete") }

    func reschedule(_ id: Int, to date: String?, keepTime: Bool = true) async throws -> TaskChange {
        try await post("/tasks/\(id)/reschedule", ["date": date ?? NSNull(), "keep_time": keepTime])
    }

    func update(_ id: Int, _ fields: [String: Any]) async throws -> TaskChange {
        try await send(request("PATCH", "/tasks/\(id)", json: try JSONSerialization.data(withJSONObject: fields)))
    }

    func delete(_ id: Int) async throws -> TaskChange { try await send(request("DELETE", "/tasks/\(id)")) }

    func setChecklist(_ itemId: Int, done: Bool) async throws -> TaskChange {
        try await send(request("PATCH", "/checklist/\(itemId)", json: try JSONSerialization.data(withJSONObject: ["done": done])))
    }

    func history(limit: Int = 50) async throws -> [ChangeSet] { try await get("/history?limit=\(limit)") }
    func undo(_ changeSetId: Int) async throws -> ChangeSet { try await post("/history/\(changeSetId)/undo") }

    func state(today: String) async throws -> AppState { try await get("/state?today=\(today)") }
    func thread() async throws -> ThreadResponse { try await get("/agent/thread") }

    func importNotion(databaseId: String) async throws -> ImportResult {
        try await post("/imports/notion", ["database_id": databaseId])
    }

    /// One file, a .zip, or several files imported together as one change set.
    func importFiles(_ files: [(name: String, data: Data)]) async throws -> ImportResult {
        let boundary = "planly-\(UUID().uuidString)"
        var body = Data()
        for file in files {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            let safeName = file.name.replacingOccurrences(of: "\"", with: "")
            body.append("Content-Disposition: form-data; name=\"files\"; filename=\"\(safeName)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
            body.append(file.data)
            body.append("\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        var upload = try request("POST", "/imports/file")
        upload.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        upload.httpBody = body
        upload.timeoutInterval = 120
        return try await send(upload)
    }

    /// GET /export → the plan file, saved to a temporary file for the share sheet.
    func export() async throws -> URL {
        let (data, response) = try await Self.session.data(for: request("GET", "/export"))
        try Self.check(response, data)
        let name = "planly-export-\(PlanDates.today()).json"
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try data.write(to: file, options: .atomic)
        return file
    }

    /// POST /agent/runs → Server-Sent Events.
    func agentRun(_ body: [String: Any]) async throws -> URLSession.AsyncBytes {
        var run = try request("POST", "/agent/runs", json: try JSONSerialization.data(withJSONObject: body))
        run.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        run.timeoutInterval = 300
        let (bytes, response) = try await Self.streamingSession.bytes(for: run)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            var data = Data()
            for try await byte in bytes { data.append(byte) }
            try Self.check(response, data)
        }
        return bytes
    }
}
