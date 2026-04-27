import Foundation
import OSLog

private let logger = Logger(subsystem: "com.korbinhillan.choresapp", category: "APIClient")

enum APIError: Error, LocalizedError {
    case invalidResponse
    case unauthorized
    case server(code: String, message: String)
    case decoding(Error)
    case transport(Error)
    case rateLimited

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "The server returned an unexpected response."
        case .unauthorized: return "You've been signed out. Please log in again."
        case .server(_, let message): return message
        case .decoding: return "Couldn't read the server response."
        case .transport(let err): return err.localizedDescription
        case .rateLimited: return "Too many requests. Please wait a moment and try again."
        }
    }
}

private struct ServerError: Decodable {
    struct Body: Decodable { let code: String; let message: String }
    let error: Body
}

// Sentinel used for fire-and-forget requests that return no meaningful body.
private struct Empty: Decodable {}

actor APIClient {
    static let shared = APIClient(baseURL: AppEnvironment.apiBaseURL)

    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    var accessToken: String?
    var onUnauthorized: (@Sendable () async -> Void)?
    var tokenRefresher: (@Sendable () async throws -> String)?
    private var refreshTask: Task<String, Error>?

    private func performRefresh() async throws -> String {
        if let existing = refreshTask {
            return try await existing.value
        }

        let task = Task {
            guard let refresher = tokenRefresher else {
                throw APIError.unauthorized
            }
            return try await refresher()
        }

        self.refreshTask = task
        defer { self.refreshTask = nil }

        do {
            let newToken = try await task.value
            self.accessToken = newToken
            return newToken
        } catch {
            await onUnauthorized?()
            throw error
        }
    }

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
    }

    // MARK: - GET / no-body requests

    func get<Response: Decodable>(_ path: String, query: [URLQueryItem]? = nil) async throws -> Response {
        try await execute(path: path, method: "GET", query: query, bodyData: nil)
    }

    // MARK: - Requests with a body

    func post<Body: Encodable, Response: Decodable>(_ path: String, body: Body) async throws -> Response {
        try await execute(path: path, method: "POST", query: nil, bodyData: try encoder.encode(body))
    }

    func put<Body: Encodable, Response: Decodable>(_ path: String, body: Body) async throws -> Response {
        try await execute(path: path, method: "PUT", query: nil, bodyData: try encoder.encode(body))
    }

    // MARK: - Fire-and-forget variants (no meaningful response body)

    func post<Body: Encodable>(_ path: String, body: Body) async throws {
        let _: Empty = try await post(path, body: body)
    }

    func put<Body: Encodable>(_ path: String, body: Body) async throws {
        let _: Empty = try await put(path, body: body)
    }

    func delete(_ path: String) async throws {
        let _: Empty = try await execute(path: path, method: "DELETE", query: nil, bodyData: nil)
    }

    // MARK: - Generic send for external call sites that need full control

    func send<Response: Decodable>(
        path: String,
        method: String = "GET",
        query: [URLQueryItem]? = nil
    ) async throws -> Response {
        try await execute(path: path, method: method, query: query, bodyData: nil)
    }

    func send<Body: Encodable, Response: Decodable>(
        path: String,
        method: String,
        body: Body,
        query: [URLQueryItem]? = nil
    ) async throws -> Response {
        try await execute(path: path, method: method, query: query, bodyData: try encoder.encode(body))
    }

    func send<Body: Encodable>(path: String, method: String, body: Body) async throws {
        let _: Empty = try await send(path: path, method: method, body: body)
    }

    func data(path: String, query: [URLQueryItem]? = nil) async throws -> Data {
        try await executeData(path: path, method: "GET", query: query, bodyData: nil)
    }

    // MARK: - Core execution

    private func execute<Response: Decodable>(
        path: String,
        method: String,
        query: [URLQueryItem]?,
        bodyData: Data?
    ) async throws -> Response {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query

        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData

        if let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await fetch(request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if http.statusCode == 401 && path != "/auth/refresh" {
            let newToken = try await performRefresh()
            request.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")

            let (retryData, retryResponse) = try await fetch(request)
            guard let retryHTTP = retryResponse as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            if retryHTTP.statusCode == 401 {
                await onUnauthorized?()
                throw APIError.unauthorized
            }
            return try decode(retryData, statusCode: retryHTTP.statusCode)
        }

        return try decode(data, statusCode: http.statusCode)
    }

    private func executeData(
        path: String,
        method: String,
        query: [URLQueryItem]?,
        bodyData: Data?
    ) async throws -> Data {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query

        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData

        if let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await fetch(request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if http.statusCode == 401 && path != "/auth/refresh" {
            let newToken = try await performRefresh()
            request.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")

            let (retryData, retryResponse) = try await fetch(request)
            guard let retryHTTP = retryResponse as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            if retryHTTP.statusCode == 401 {
                await onUnauthorized?()
                throw APIError.unauthorized
            }
            try validateDataResponse(retryData, statusCode: retryHTTP.statusCode)
            return retryData
        }

        try validateDataResponse(data, statusCode: http.statusCode)
        return data
    }

    private func fetch(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw APIError.transport(error)
        }
    }

    private func decode<T: Decodable>(_ data: Data, statusCode: Int) throws -> T {
        if statusCode == 429 { throw APIError.rateLimited }
        if statusCode >= 400 {
            if let err = try? decoder.decode(ServerError.self, from: data) {
                throw APIError.server(code: err.error.code, message: err.error.message)
            }
            throw APIError.invalidResponse
        }
        if data.isEmpty {
            if T.self == Empty.self {
                return Empty() as! T
            }
            throw APIError.invalidResponse
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            logger.error("Decoding error for \(T.self): \(error)")
            throw APIError.decoding(error)
        }
    }

    private func validateDataResponse(_ data: Data, statusCode: Int) throws {
        if statusCode == 429 { throw APIError.rateLimited }
        if statusCode >= 400 {
            if let err = try? decoder.decode(ServerError.self, from: data) {
                throw APIError.server(code: err.error.code, message: err.error.message)
            }
            throw APIError.invalidResponse
        }
    }
}

// APIClient helpers callable from AuthStore
extension APIClient {
    func setAccessToken(_ token: String?) async { self.accessToken = token }
    func setTokenRefresher(_ r: (@Sendable () async throws -> String)?) async { self.tokenRefresher = r }
    func setOnUnauthorized(_ h: (@Sendable () async -> Void)?) async { self.onUnauthorized = h }
}
