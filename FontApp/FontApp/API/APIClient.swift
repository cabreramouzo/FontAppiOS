import Foundation

/// A failed request. `status` 0 means the server could not be reached (or timed out).
nonisolated struct APIError: Error, Equatable, Sendable {
    let status: Int
    /// The server's sentence, in Spanish. For logs; shown only when `code` is unknown.
    let reason: String?
    /// Stable code such as `user.emailTaken`. Translate by this, never show it raw.
    let code: String?
    /// From a 429's `Retry-After`. Show it; never retry in a loop.
    let retryAfter: TimeInterval?

    static let network = APIError(status: 0, reason: nil, code: nil, retryAfter: nil)
}

/// Read-only client for the FontApp API.
///
/// Stateless and `Sendable`: screens hold a copy and call it from tasks. There is no
/// session yet, so no `Authorization` header.
nonisolated struct APIClient: Sendable {
    static let production = URL(string: "https://fontapp.fly.dev")!
    static let shared = APIClient(baseURL: production)

    let baseURL: URL
    var session: URLSession = .shared

    /// Reads have a way out (the map keeps what it had, the list shows a retry), so they
    /// give up early. The web measured `/fonts/map` at 0.18–0.45 s in production.
    var readTimeout: TimeInterval = 8

    // MARK: Endpoints

    func map(box: MapBox, width: Int, height: Int) async throws -> MapResponse {
        try await get("/fonts/map", query: box.queryItems + [
            URLQueryItem(name: "width", value: String(width)),
            URLQueryItem(name: "height", value: String(height)),
        ])
    }

    func font(_ id: UUID) async throws -> FontDetail {
        try await get("/fonts/\(id.uuidString)")
    }

    func comments(of id: UUID) async throws -> [CommentResponse] {
        try await get("/fonts/\(id.uuidString)/comments")
    }

    func reports(of id: UUID) async throws -> [ReportResponse] {
        try await get("/fonts/\(id.uuidString)/report")
    }

    /// Recent activity. With `near`, only what happened within `km` of that point.
    func activity(limit: Int = 30, near: (latitude: Double, longitude: Double)? = nil,
                  km: Double? = nil, before: Double? = nil) async throws -> [ActivityItem] {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let near {
            query.append(URLQueryItem(name: "lat", value: String(near.latitude)))
            query.append(URLQueryItem(name: "long", value: String(near.longitude)))
            if let km { query.append(URLQueryItem(name: "km", value: String(km))) }
        }
        if let before { query.append(URLQueryItem(name: "before", value: String(before))) }
        return try await get("/activity", query: query)
    }

    /// Resolves an image path from the API (`/uploads/x.jpg` or an absolute URL).
    func imageURL(_ path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        if path.hasPrefix("http://") || path.hasPrefix("https://") { return URL(string: path) }
        return URL(string: path, relativeTo: baseURL)?.absoluteURL
    }

    // MARK: Transport

    @concurrent func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!, timeoutInterval: readTimeout)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw APIError.network
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.network }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.error(status: http.statusCode, data: data,
                             retryAfter: http.value(forHTTPHeaderField: "Retry-After"))
        }
        return try Self.decoder.decode(T.self, from: data)
    }

    static func error(status: Int, data: Data, retryAfter: String?) -> APIError {
        struct Body: Decodable { let reason: String?; let code: String? }
        let body = try? JSONDecoder().decode(Body.self, from: data)
        let seconds = retryAfter.flatMap(TimeInterval.init).flatMap { $0 > 0 ? $0 : nil }
        return APIError(status: status, reason: body?.reason, code: body?.code, retryAfter: seconds)
    }

    /// ISO-8601 in UTC, with or without fractional seconds.
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = try? Date(text, strategy: .iso8601) { return date }
            if let date = try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) {
                return date
            }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Not an ISO-8601 date: \(text)"))
        }
        return decoder
    }()
}
