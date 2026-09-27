import Foundation
import Synchronization

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

/// Which backend the app talks to.
///
/// Debug builds use the local backend (`swift run App serve` in FontAppBE), whose data is
/// seeded: writing reviews and photos while developing must never reach production. Pass
/// `-FontAppAPI https://fontapp.fly.dev` as a launch argument to point a Debug build
/// elsewhere (a phone cannot reach the Mac's 127.0.0.1). Release always uses production.
nonisolated enum APIEnvironment {
    static let production = URL(string: "https://fontapp.fly.dev")!
    static let local = URL(string: "http://127.0.0.1:8080")!

    static var baseURL: URL {
        #if DEBUG
        if let override = UserDefaults.standard.string(forKey: "FontAppAPI"),
           let url = URL(string: override) {
            return url
        }
        return local
        #else
        return production
        #endif
    }
}

/// The session token, readable from any request. Only `SessionStore` writes it.
nonisolated final class Credentials: Sendable {
    static let shared = Credentials()
    /// Posted when the server rejects the stored token (401 on a request that carried it):
    /// expired, revoked from another device, or the account is gone.
    static let rejected = Notification.Name("FontAppSessionRejected")

    private let token = Mutex<String?>(nil)

    var current: String? { token.withLock { $0 } }

    func set(_ value: String?) { token.withLock { $0 = value } }
}

/// A response whose body does not matter (204, or a JSON the app does not use).
nonisolated struct Ignored: Decodable, Sendable {}

/// Client for the FontApp API.
///
/// Stateless and `Sendable`: screens hold a copy and call it from tasks. The bearer token
/// comes from `Credentials` on every request.
nonisolated struct APIClient: Sendable {
    static let shared = APIClient(baseURL: APIEnvironment.baseURL)

    let baseURL: URL
    var session: URLSession = .shared
    var credentials: Credentials = .shared

    /// Reads have a way out (the map keeps what it had, the list shows a retry), so they
    /// give up early. The web measured `/fonts/map` at 0.18–0.45 s in production.
    var readTimeout: TimeInterval = 8
    /// A write cut short may still have landed on the server: waiting longer is cheaper
    /// than a duplicate. Same figures as the web.
    var writeTimeout: TimeInterval = 12
    var uploadTimeout: TimeInterval = 45

    // MARK: Reading

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

    /// Every fountain in a box, as summaries (at most 3,000; the map's legacy endpoint).
    /// For offline zones, where clusters would be of no use.
    func fontsInBounds(_ box: MapBox) async throws -> [FontSummary] {
        try await get("/fonts/in-bounds", query: box.queryItems)
    }

    /// The nearest fountains, by distance.
    func nearby(latitude: Double, longitude: Double, quantity: Int = 10) async throws -> [FontSummary] {
        try await get("/fonts/near", query: [
            URLQueryItem(name: "lat", value: String(latitude)),
            URLQueryItem(name: "long", value: String(longitude)),
            URLQueryItem(name: "quantity", value: String(quantity)),
        ])
    }

    func createFont(_ font: NewFont, queuedOffline: Bool = false) async throws -> FontDetail {
        try await send("POST", "/fonts", body: .json(try JSONEncoder().encode(font)),
                       queuedOffline: queuedOffline, timeout: writeTimeout)
    }

    /// Fountains by name. The server requires a term and, for the public, caps the pages.
    func searchFonts(_ term: String, per: Int = 20) async throws -> [FontSummary] {
        struct Page: Decodable { let items: [FontSummary] }
        let page: Page = try await get("/fonts", query: [
            URLQueryItem(name: "search", value: term),
            URLQueryItem(name: "per", value: String(per)),
        ])
        return page.items
    }

    // MARK: Session

    /// Username **or email** and password, as HTTP Basic.
    func login(user: String, password: String) async throws -> LoginResponse {
        let basic = Data("\(user):\(password)".utf8).base64EncodedString()
        return try await send("POST", "/auth/login", authorization: "Basic \(basic)", timeout: writeTimeout)
    }

    func me() async throws -> UserResponse {
        try await get("/auth/me")
    }

    func logout() async throws {
        let _: Ignored = try await send("POST", "/auth/logout", timeout: writeTimeout)
    }

    // MARK: Contributing

    /// `queuedOffline`: it was written without signal and sent later from the outbox.
    /// The server keeps the mark for moderation; nothing else hangs from it.
    /// A first status with no chips' intent: the fountain's own first report.
    func postStatus(on fontID: UUID, _ status: String, queuedOffline: Bool = false) async throws {
        let body = try JSONEncoder().encode(["waterStatus": status])
        let _: Ignored = try await send("POST", "/fonts/\(fontID.uuidString)/comments", body: .json(body),
                                        queuedOffline: queuedOffline, timeout: writeTimeout)
    }

    func postReview(on fontID: UUID, _ review: NewReview, queuedOffline: Bool = false) async throws -> CommentResponse {
        try await send("POST", "/fonts/\(fontID.uuidString)/comments",
                       body: .json(try JSONEncoder().encode(review)), queuedOffline: queuedOffline,
                       timeout: writeTimeout)
    }

    func deleteReview(_ commentID: UUID, on fontID: UUID) async throws {
        let _: Ignored = try await send("DELETE", "/fonts/\(fontID.uuidString)/comments/\(commentID.uuidString)",
                                        timeout: writeTimeout)
    }

    /// "Still the same" on a review, or taking it back.
    func confirm(_ commentID: UUID, on fontID: UUID, _ on: Bool) async throws -> CommentResponse {
        try await send(on ? "POST" : "DELETE",
                       "/fonts/\(fontID.uuidString)/comments/\(commentID.uuidString)/confirm",
                       timeout: writeTimeout)
    }

    /// Uploads a JPEG and returns its URL. The EXIF travels as separate fields because the
    /// re-encoded JPEG no longer carries it.
    func uploadImage(_ jpeg: Data, meta: PhotoMeta) async throws -> String {
        var form = MultipartForm()
        if let takenAt = meta.takenAt { form.add("takenAt", takenAt.formatted(.iso8601)) }
        if let latitude = meta.latitude, let longitude = meta.longitude {
            form.add("latitude", String(latitude))
            form.add("longitude", String(longitude))
        }
        form.addFile("file", filename: "photo.jpg", contentType: "image/jpeg", data: jpeg)
        struct Uploaded: Decodable { let url: String }
        let uploaded: Uploaded = try await send("POST", "/images", body: .multipart(form), timeout: uploadTimeout)
        return uploaded.url
    }

    /// Sets the photo of a fountain that has none. Replacing one is for its creator or
    /// an admin (403 otherwise).
    func setFontPhoto(_ fontID: UUID, image: String, queuedOffline: Bool = false) async throws {
        let body = try JSONEncoder().encode(["image": image])
        let _: Ignored = try await send("PUT", "/fonts/\(fontID.uuidString)/photo",
                                        body: .json(body), queuedOffline: queuedOffline, timeout: writeTimeout)
    }

    /// Resolves an image path from the API (`/uploads/x.jpg` or an absolute URL).
    func imageURL(_ path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        if path.hasPrefix("http://") || path.hasPrefix("https://") { return URL(string: path) }
        return URL(string: path, relativeTo: baseURL)?.absoluteURL
    }

    // MARK: Transport

    enum Body {
        case none
        case json(Data)
        case multipart(MultipartForm)
    }

    func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        try await send("GET", path, query: query, timeout: readTimeout)
    }

    @concurrent func send<T: Decodable>(_ method: String, _ path: String, query: [URLQueryItem] = [],
                                        body: Body = .none, authorization: String? = nil,
                                        queuedOffline: Bool = false,
                                        timeout: TimeInterval) async throws -> T {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        // No HTTP cache: after a contribution the next read must show it, and the map and
        // the lists already decide themselves when to ask again.
        var request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if queuedOffline { request.setValue("1", forHTTPHeaderField: "X-FontApp-Queued-Offline") }
        let bearer = authorization == nil ? credentials.current : nil
        if let authorization {
            request.setValue(authorization, forHTTPHeaderField: "Authorization")
        } else if let bearer {
            request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }
        switch body {
        case .none:
            break
        case .json(let data):
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = data
        case .multipart(let form):
            request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
            request.httpBody = form.body
        }

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
            if http.statusCode == 401, let bearer {
                NotificationCenter.default.post(name: Credentials.rejected, object: bearer)
            }
            throw Self.error(status: http.statusCode, data: data,
                             retryAfter: http.value(forHTTPHeaderField: "Retry-After"))
        }
        if T.self == Ignored.self { return Ignored() as! T }
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

/// A `multipart/form-data` body.
nonisolated struct MultipartForm: Sendable {
    let boundary = "FontApp-\(UUID().uuidString)"
    private var data = Data()

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    mutating func add(_ name: String, _ value: String) {
        data.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
    }

    mutating func addFile(_ name: String, filename: String, contentType: String, data file: Data) {
        data.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\nContent-Type: \(contentType)\r\n\r\n".utf8))
        data.append(file)
        data.append(Data("\r\n".utf8))
    }

    /// The closing boundary is added when the body is read.
    var body: Data { data + Data("--\(boundary)--\r\n".utf8) }
}
