import Foundation
import MapKit
import Testing
@testable import FontApp

/// The app's own translations for one language, whatever the simulator's language is.
private func bundle(_ lang: String) -> Bundle {
    Bundle(path: Bundle.main.path(forResource: lang, ofType: "lproj")!)!
}

private func date(_ iso: String) -> Date { try! Date(iso, strategy: .iso8601) }

struct DecodingTests {
    // Shapes copied from production responses on 27/09/2026: null fields are omitted.
    @Test func mapResponse() throws {
        let json = """
        {"total":1,"clusters":[],"fonts":[{"recentStatusConflict":false,"createdAt":"2026-08-11T01:10:02Z",
        "region":"Barcelona","id":"8D0DFB7F-CC13-445A-B09C-A8FD2D236363","longitude":2.0981,
        "recentStatusReporters":0,"description":"© ICGC/ACA","latitude":41.7948,"name":"Font Falsía",
        "source":"spring","admin1":"ES-CT","latestConfirmations":0,"country":"Spain"}]}
        """
        let map = try APIClient.decoder.decode(MapResponse.self, from: Data(json.utf8))
        #expect(map.fonts.first?.name == "Font Falsía")
        #expect(map.fonts.first?.source == .spring)
        #expect(map.fonts.first?.lastWaterStatus == nil)
    }

    @Test func fontDetailWithNullName() throws {
        let json = """
        {"image":"https://example.org/a.jpg","creator":{"id":"DCC2DB40-0705-4D0C-9523-8D3898E863EC"},
        "retiredAt":null,"moderationState":"visible","admin1":"ES-CT","name":null,"lastWaterStatus":"flowing",
        "longitude":2.25,"source":"tap","id":"4DCBC5A0-799A-4CED-9C18-5F0BD8CB3D33","latitude":41.92,
        "municipality":"Vic","lastUpdate":"2026-09-25T14:53:13Z","duplicateOf":null,"statusConflict":false,
        "description":null,"createdAt":"2026-09-25T14:48:25Z","region":"Barcelona","drinkable":null,
        "mayor":null,"country":"Spain"}
        """
        let font = try APIClient.decoder.decode(FontDetail.self, from: Data(json.utf8))
        #expect(font.name == nil)
        #expect(font.lastUpdate == date("2026-09-25T14:53:13Z"))
    }

    @Test func activityToleratesUnknownKinds() throws {
        let json = """
        [{"author":"font199","createdAt":"2026-09-25T14:48:25Z","kind":"review","region":"Barcelona",
        "fontID":"4DCBC5A0-799A-4CED-9C18-5F0BD8CB3D33","waterStatus":"flowing","cursor":1790347705.463326},
        {"createdAt":"2026-09-25T14:48:25Z","kind":"somethingNew","fontID":"4DCBC5A0-799A-4CED-9C18-5F0BD8CB3D33",
        "cursor":1790347705.1}]
        """
        let items = try APIClient.decoder.decode([ActivityItem].self, from: Data(json.utf8))
        #expect(items.map(\.kind) == [.review, .other])
    }

    @Test func fractionalSecondsDates() throws {
        let d = try APIClient.decoder.decode([Date].self, from: Data(#"["2026-09-25T14:48:25.123Z"]"#.utf8))
        #expect(d.count == 1)
    }
}

struct ConfidenceTests {
    let now = date("2026-09-27T12:00:00Z")

    @Test func conflictBeatsEverything() {
        let e = ConfidenceEvidence(lastWaterStatus: "flowing", lastUpdate: now, latestConfirmations: 3,
                                   recentStatusConflict: true)
        #expect(Confidence.level(of: e, now: now) == .disputed)
    }

    @Test func categories() {
        #expect(Confidence.level(of: ConfidenceEvidence(), now: now) == .unverified)
        let recent = ConfidenceEvidence(lastWaterStatus: "dry", lastUpdate: now.addingTimeInterval(-86_400 * 3))
        #expect(Confidence.level(of: recent, now: now) == .recent)
        var confirmed = recent
        confirmed.latestConfirmations = 1
        #expect(Confidence.level(of: confirmed, now: now) == .verified)
        let old = ConfidenceEvidence(lastWaterStatus: "flowing", lastUpdate: now.addingTimeInterval(-86_400 * 31))
        #expect(Confidence.level(of: old, now: now) == .stale)
        // Exactly 30 days is still fresh, as on the web.
        let edge = ConfidenceEvidence(lastWaterStatus: "flowing", lastUpdate: now.addingTimeInterval(-86_400 * 30.5))
        #expect(Confidence.level(of: edge, now: now) == .recent)
    }

    @Test func evidenceFromReviewsSeesConflict() {
        func review(_ status: String, daysAgo: Double, user: UUID = UUID()) -> CommentResponse {
            CommentResponse(id: UUID(), userID: user, username: nil, body: "", rating: nil, waterStatus: status,
                            image: nil, createdAt: now.addingTimeInterval(-86_400 * daysAgo),
                            confirmations: 0, lastConfirmedAt: nil, confirmedByMe: nil, confirmedInstead: nil)
        }
        let e = Confidence.evidence(from: [review("flowing", daysAgo: 1), review("dry", daysAgo: 5)], now: now)
        #expect(e.lastWaterStatus == "flowing")
        #expect(e.recentStatusConflict)
        #expect(e.recentStatusReporters == 2)
        #expect(Confidence.level(of: e, now: now) == .disputed)
        // "unknown" and old reviews do not count as conflict.
        let calm = Confidence.evidence(from: [review("flowing", daysAgo: 1), review("unknown", daysAgo: 2),
                                              review("dry", daysAgo: 40)], now: now)
        #expect(!calm.recentStatusConflict)
    }
}

struct MapBoxTests {
    @Test func clampsWorldView() throws {
        let region = MKCoordinateRegion(center: .init(latitude: 10, longitude: 170),
                                        span: .init(latitudeDelta: 200, longitudeDelta: 400))
        let box = try #require(MapBox(region: region))
        #expect(box.minLat == -90 && box.maxLat == 90)
        #expect(box.minLong == -180 && box.maxLong == 180)
    }

    @Test func antimeridianAsksForAllLongitudes() throws {
        let region = MKCoordinateRegion(center: .init(latitude: -17, longitude: 179),
                                        span: .init(latitudeDelta: 2, longitudeDelta: 4))
        let box = try #require(MapBox(region: region))
        #expect(box.minLong == -180 && box.maxLong == 180)
        #expect(box.minLat == -18 && box.maxLat == -16)
    }

    @Test func rejectsEmptyAndNaN() {
        #expect(MapBox(minLat: 1, maxLat: 1, minLong: 0, maxLong: 1) == nil)
        #expect(MapBox(minLat: .nan, maxLat: 1, minLong: 0, maxLong: 1) == nil)
    }
}

struct DefaultMapViewTests {
    @Test func byTimeZone() {
        #expect(DefaultMapView.forTimeZone("America/Mexico_City").latitude == 23.6)
        #expect(DefaultMapView.forTimeZone("America/Monterrey") == DefaultMapView.forTimeZone("America/Mexico_City"))
        #expect(DefaultMapView.forTimeZone("America/Argentina/Cordoba").longitude == -63.6)
        #expect(DefaultMapView.forTimeZone("America/Sao_Paulo").zoom == 4)
        #expect(DefaultMapView.forTimeZone("Europe/Andorra").zoom == 10)
        #expect(DefaultMapView.forTimeZone("Asia/Kolkata") == .fallback)
        #expect(DefaultMapView.forTimeZone(nil) == .fallback)
    }
}

struct TextTests {
    @Test func errorsTranslateByCode() {
        let es = bundle("es")
        let known = APIError(status: 409, reason: "El correo ya está en uso", code: "user.emailTaken", retryAfter: nil)
        #expect(ErrorText.describe(known, bundle: bundle("en")) == L10n.t("err.user.emailTaken", bundle: bundle("en")))
        #expect(!ErrorText.describe(known, bundle: bundle("en")).contains("err."))
        let unknown = APIError(status: 400, reason: "Frase del servidor", code: "brand.newCode", retryAfter: nil)
        #expect(ErrorText.describe(unknown, bundle: es) == "Frase del servidor")
        let limited = APIError(status: 429, reason: nil, code: nil, retryAfter: 125)
        #expect(ErrorText.describe(limited, bundle: es).contains("3"))
        #expect(ErrorText.describe(APIError.network, bundle: es) == L10n.t("error.network", bundle: es))
    }

    @Test func relativeTimeAndNames() {
        let ca = bundle("ca")
        let now = date("2026-09-27T12:00:00Z")
        #expect(RelativeTime.string(since: now.addingTimeInterval(-7200), now: now, bundle: ca) == "fa 2 h")
        #expect(RelativeTime.string(since: now.addingTimeInterval(-86_400 * 1.5), now: now, bundle: ca) == "ahir")
        #expect(L10n.t("font.unnamed", bundle: ca) == "Font sense nom")
        #expect(L10n.t("font.unnamed", bundle: bundle("es")) == "Fuente sin nombre")
    }
}

struct ReloadThrottleTests {
    @Test func followingReloadsAtMostEverySixSeconds() {
        let t0 = date("2026-09-27T12:00:00Z")
        var throttle = ReloadThrottle()
        #expect(throttle.decide(following: true, now: t0) == .now)
        throttle.didRequest(at: t0)
        #expect(throttle.decide(following: true, now: t0.addingTimeInterval(2)) == .at(t0.addingTimeInterval(6)))
        #expect(throttle.decide(following: true, now: t0.addingTimeInterval(6)) == .now)
        // A move by hand is an intention: always at once.
        #expect(throttle.decide(following: false, now: t0.addingTimeInterval(1)) == .now)
    }
}

struct ReportThreadTests {
    @Test func repliesFollowTheirParent() {
        func report(_ id: UUID = UUID(), parent: UUID? = nil, minutesAgo: Double) -> ReportResponse {
            ReportResponse(id: id, username: nil, message: "", isIncident: false, incidentKind: nil,
                           createdAt: Date(timeIntervalSince1970: 1_000_000 - minutesAgo * 60), parentID: parent,
                           resolvedAt: nil, resolvedBy: nil)
        }
        let old = UUID(), new = UUID()
        let list = [report(new, minutesAgo: 1), report(parent: old, minutesAgo: 2), report(old, minutesAgo: 10)]
        let threaded = FontDetailModel.threaded(list)
        #expect(threaded.map(\.parentID) == [nil, nil, old])
        #expect(threaded.first?.id == new)
    }
}

struct SessionModelTests {
    @Test func rolesAndStaff() throws {
        let decode = { (raw: String) in try JSONDecoder().decode(UserRole.self, from: Data("\"\(raw)\"".utf8)) }
        #expect(try decode("moderator").isStaff)
        #expect(try decode("owner").isStaff)
        #expect(try !decode("user").isStaff)
        // A role this build does not know must not grant staff colours.
        #expect(try decode("superhero") == .user)
    }

    @Test func multipartIsClosed() {
        var form = MultipartForm()
        form.add("takenAt", "2026-09-27T10:00:00Z")
        form.addFile("file", filename: "photo.jpg", contentType: "image/jpeg", data: Data([0xFF, 0xD8]))
        let text = String(decoding: form.body, as: UTF8.self)
        #expect(text.contains("name=\"takenAt\"\r\n\r\n2026-09-27T10:00:00Z\r\n"))
        #expect(text.contains("filename=\"photo.jpg\"\r\nContent-Type: image/jpeg"))
        #expect(text.hasSuffix("--\(form.boundary)--\r\n"))
    }
}

struct RemoteReviewTests {
    let fountain = CLLocationCoordinate2D(latitude: 41.8105, longitude: 2.0977)
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func fix(km: Double, accuracy: Double, age: TimeInterval = 10) -> CLLocation {
        // ~111 km per degree of latitude.
        CLLocation(coordinate: .init(latitude: fountain.latitude + km / 111.2, longitude: fountain.longitude),
                   altitude: 0, horizontalAccuracy: accuracy, verticalAccuracy: -1,
                   timestamp: now.addingTimeInterval(-age))
    }

    @Test func farAwayIsRoundedDistance() {
        #expect(RemoteReview.distance(from: fix(km: 1.44, accuracy: 20), to: fountain, now: now) == 1400)
        #expect(RemoteReview.distance(from: fix(km: 12.4, accuracy: 20), to: fountain, now: now) == 12_000)
    }

    @Test func benefitOfTheDoubt() {
        // Near, vague, stale or missing: ask nothing.
        #expect(RemoteReview.distance(from: fix(km: 0.3, accuracy: 10), to: fountain, now: now) == nil)
        #expect(RemoteReview.distance(from: fix(km: 1.4, accuracy: 600), to: fountain, now: now) == nil)
        #expect(RemoteReview.distance(from: fix(km: 5, accuracy: 1500), to: fountain, now: now) == nil)
        #expect(RemoteReview.distance(from: fix(km: 5, accuracy: 20, age: 600), to: fountain, now: now) == nil)
        #expect(RemoteReview.distance(from: nil, to: fountain, now: now) == nil)
    }

    @Test func kmLabelInTheReadersLocale() {
        #expect(RemoteReview.kmLabel(1400, locale: Locale(identifier: "ca_ES")) == "1,4")
        #expect(RemoteReview.kmLabel(12_000, locale: Locale(identifier: "en_US")) == "12")
    }
}

/// Answers requests from a table and records what was sent.
final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responses: [String: (Int, String)] = [:]
    nonisolated(unsafe) static var sent: [(method: String, path: String, body: Data?)] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let method = request.httpMethod ?? "GET"
        let path = request.url?.path() ?? ""
        var body = request.httpBody
        if body == nil, let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }
                data.append(buffer, count: n)
            }
            stream.close()
            body = data
        }
        Self.sent.append((method, path, body))
        let (status, json) = Self.responses["\(method) \(path)"] ?? (404, #"{"reason":"stub"}"#)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func client() -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return APIClient(baseURL: URL(string: "https://stub.test")!, session: URLSession(configuration: config),
                         credentials: Credentials())
    }
}

@Suite(.serialized)
struct QuickReviewTests {
    let font = UUID()
    let comment = UUID()

    private func reviewJSON(confirmedInstead: Bool) -> String {
        """
        {"id":"\(comment.uuidString)","body":"","createdAt":"2026-09-27T10:00:00Z","waterStatus":"flowing",
        "confirmedInstead":\(confirmedInstead)}
        """
    }

    @Test func sendsTheIntentAndCanUndoAConfirmation() async throws {
        StubProtocol.sent = []
        StubProtocol.responses = [
            "POST /fonts/\(font.uuidString)/comments": (200, reviewJSON(confirmedInstead: true)),
            "DELETE /fonts/\(font.uuidString)/comments/\(comment.uuidString)/confirm": (200, reviewJSON(confirmedInstead: false)),
        ]
        let model = QuickReviewModel(fontID: font, coordinate: .init(latitude: 41.81, longitude: 2.10),
                                     api: StubProtocol.client())
        #expect(await model.tap(.flowing, fix: nil))
        let body = try #require(StubProtocol.sent.first?.body)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["waterStatus"] as? String == "flowing")
        #expect(json["confirmIfUnchanged"] as? Bool == true)
        #expect(json["remoteDistanceM"] == nil)
        #expect(model.canUndo)

        // It became a "still the same": undoing takes the confirmation back, it does not
        // delete someone else's review.
        #expect(await model.undo())
        #expect(StubProtocol.sent.last?.method == "DELETE")
        #expect(StubProtocol.sent.last?.path.hasSuffix("/confirm") == true)
        #expect(model.state == .undone)
        #expect(!model.canUndo)
    }

    @Test func farAwayAsksOnceAndSendsTheDistance() async throws {
        StubProtocol.sent = []
        StubProtocol.responses = ["POST /fonts/\(font.uuidString)/comments": (201, reviewJSON(confirmedInstead: false))]
        let model = QuickReviewModel(fontID: font, coordinate: .init(latitude: 41.81, longitude: 2.10),
                                     api: StubProtocol.client())
        let barcelona = CLLocation(coordinate: .init(latitude: 41.3874, longitude: 2.1686), altitude: 0,
                                   horizontalAccuracy: 20, verticalAccuracy: -1, timestamp: .now)
        #expect(await model.tap(.dry, fix: barcelona) == false)
        let question = try #require(model.remoteQuestion)
        #expect(StubProtocol.sent.isEmpty)
        #expect(await model.confirmRemote(question))
        let body = try #require(StubProtocol.sent.first?.body)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["remoteDistanceM"] as? Int == 47_000)

        // Asked once per fountain: the next tap goes straight through, distance included.
        #expect(await model.tap(.dry, fix: barcelona))
        #expect(model.remoteQuestion == nil)
        #expect(StubProtocol.sent.count == 2)
    }
}
