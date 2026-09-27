import Foundation
import ImageIO
import MapKit
import UniformTypeIdentifiers
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

/// Every suite that uses `StubProtocol` lives inside this one, which runs them one at a
/// time: the stub's table is static and shared.
@Suite(.serialized) struct StubbedNetwork {}

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
        // -1: no signal.
        if status == -1 {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
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

/// Shares `StubProtocol`'s static table with the other stubbed suites, so they must
/// not run at the same time.
extension StubbedNetwork {
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
}

struct PhotoPreparerTests {
    func phoneJPEG() throws -> Data { try phonePhoto() }

    /// A 4000x3000 JPEG with a capture date and a position, like a phone photo.
    private func phonePhoto() throws -> Data {
        let context = try #require(CGContext(data: nil, width: 4000, height: 3000, bitsPerComponent: 8,
                                             bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 4000, height: 3000))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        let properties: [CFString: Any] = [
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: "2026:09:27 10:15:03",
                kCGImagePropertyExifOffsetTimeOriginal: "+02:00",
            ],
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 41.8105, kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 2.0977, kCGImagePropertyGPSLongitudeRef: "E",
            ],
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    @Test func keepsTheExifAsFieldsAndShrinksThePhoto() throws {
        let prepared = try PhotoPreparer.prepare(try phonePhoto())
        #expect(prepared.meta.takenAt == date("2026-09-27T08:15:03Z"))
        #expect(abs((prepared.meta.latitude ?? 0) - 41.8105) < 0.0001)
        #expect(abs((prepared.meta.longitude ?? 0) - 2.0977) < 0.0001)

        let source = try #require(CGImageSourceCreateWithData(prepared.jpeg as CFData, nil))
        let props = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(props[kCGImagePropertyPixelWidth] as? Int == PhotoPreparer.maxPixelSize)
        // The uploaded file itself no longer says where it was taken.
        #expect(props[kCGImagePropertyGPSDictionary] == nil)
    }

    @Test func exifDateWithoutOffsetUsesTheDeviceZone() {
        let madrid = TimeZone(identifier: "Europe/Madrid")!
        #expect(PhotoPreparer.exifDate("2026:09:27 10:15:03", offset: nil, timeZone: madrid) == date("2026-09-27T08:15:03Z"))
        #expect(PhotoPreparer.exifDate("2026:09:27 10:15:03", offset: "-05:00") == date("2026-09-27T15:15:03Z"))
    }
}

struct LeftoverTests {
    @Test func overlappingClustersJoinAndKeepTheCount() {
        let a = MapCluster(latitude: 41.0, longitude: 2.0, count: 300)
        let b = MapCluster(latitude: 41.1, longitude: 2.0, count: 100)
        let far = MapCluster(latitude: 45.0, longitude: 2.0, count: 7)
        // One point per 0.01° of latitude: a and b are 10 pt apart, far is 400 pt away.
        let merged = ClusterMerge.merge([b, far, a]) { CGPoint(x: 0, y: $0.latitude * 100) }
        #expect(merged.count == 2)
        #expect(merged.map(\.count).reduce(0, +) == 407)
        let joined = merged.first { $0.count == 400 }
        // Weighted towards the bigger one.
        #expect(abs((joined?.latitude ?? 0) - 41.025) < 0.0001)
    }

    @Test func newsRemembersScopeAndRadius() {
        let defaults = UserDefaults(suiteName: "news-\(UUID().uuidString)")!
        let first = NewsModel(defaults: defaults)
        #expect(first.scope == .near && first.km == 5)
        first.scope = .everywhere
        first.km = 25
        let again = NewsModel(defaults: defaults)
        #expect(again.scope == .everywhere)
        #expect(again.km == 25)
    }
}

/// Shares `StubProtocol`'s static table with the other stubbed suites, so they must
/// not run at the same time.
extension StubbedNetwork {
struct OutboxTests {
    let font = UUID()
    let me = UUID()
    let review = NewReview(waterStatus: "flowing", confirmIfUnchanged: true, remoteDistanceM: nil)

    private func outbox(_ dir: URL) -> Outbox {
        let box = Outbox(directory: dir, api: StubProtocol.client())
        box.currentUserID = me
        return box
    }

    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "outbox-\(UUID().uuidString)")
    }

    private var commentPath: String { "POST /fonts/\(font.uuidString)/comments" }
    private let okReview = #"{"id":"00000000-0000-0000-0000-000000000001","body":"","createdAt":"2026-09-27T10:00:00Z"}"#

    @Test func survivesARestartAndSendsMarkedAsOffline() async {
        StubProtocol.sent = []
        StubProtocol.responses = [commentPath: (201, okReview)]
        let dir = tempDir()
        outbox(dir).enqueueReview(review, fontID: font, fontName: "Font del Faig")
        // A new instance on the same folder: the app was killed and opened again.
        let reopened = outbox(dir)
        #expect(reopened.items.count == 1)
        #expect(await reopened.flush() == 1)
        #expect(reopened.items.isEmpty)
        #expect(outbox(dir).items.isEmpty)
    }

    @Test func transientFailuresKeepItForEver() async {
        StubProtocol.responses = [commentPath: (503, #"{"reason":"down"}"#)]
        let box = outbox(tempDir())
        box.enqueueReview(review, fontID: font, fontName: nil)
        for _ in 0..<5 { await box.flush() }
        #expect(box.items.count == 1)
        #expect(box.items.first?.attempts == 0)
    }

    @Test func aDefinitiveRejectionIsDroppedAfterThreeTries() async {
        StubProtocol.responses = [commentPath: (404, #"{"reason":"gone","code":"font.notFound"}"#)]
        let box = outbox(tempDir())
        box.enqueueReview(review, fontID: font, fontName: nil)
        await box.flush()
        await box.flush()
        #expect(box.items.first?.attempts == 2)
        await box.flush()
        #expect(box.items.isEmpty)
    }

    @Test func anExpiredSessionWaitsForASignIn() async {
        StubProtocol.responses = [commentPath: (401, #"{"reason":"no"}"#)]
        let box = outbox(tempDir())
        box.enqueueReview(review, fontID: font, fontName: nil)
        await box.flush()
        #expect(box.needsAuth)
        StubProtocol.responses = [commentPath: (201, okReview)]
        await box.flush()
        #expect(box.items.count == 1, "not retried until a new sign-in")
        box.sessionChanged(to: me)
        #expect(await box.flush() == 1)
    }

    @Test func onlyTheAccountThatQueuedItSendsIt() async {
        StubProtocol.sent = []
        StubProtocol.responses = [commentPath: (201, okReview)]
        let box = outbox(tempDir())
        box.enqueueReview(review, fontID: font, fontName: nil)
        box.sessionChanged(to: UUID())
        #expect(await box.flush() == 0)
        #expect(StubProtocol.sent.isEmpty)
        #expect(box.othersCount == 1)
        box.sessionChanged(to: nil)
        #expect(box.othersCount == 0, "signed out, nothing is someone else's")
        #expect(await box.flush() == 0)
        box.sessionChanged(to: me)
        #expect(await box.flush() == 1)
    }

    @Test func withoutSignalAReviewAndAPhotoGoToTheOutbox() async throws {
        StubProtocol.responses = [
            commentPath: (-1, ""),
            "POST /images": (-1, ""),
        ]
        let box = outbox(tempDir())
        let quick = QuickReviewModel(fontID: font, fontName: "Font del Faig",
                                     coordinate: .init(latitude: 41.81, longitude: 2.10),
                                     api: StubProtocol.client(), outbox: box)
        #expect(await quick.tap(.dry, fix: nil) == false)
        guard case .queued = quick.state else { Issue.record("not queued: \(quick.state)"); return }
        #expect(quick.canUndo)

        let photo = PhotoUploadModel(fontID: font, fontName: "Font del Faig", api: StubProtocol.client(), outbox: box)
        #expect(await photo.upload(cameraJPEG: try PhotoPreparerTests().phoneJPEG(), fix: nil) == false)
        #expect(photo.state == .queued)
        #expect(box.items.map(\.kind) == [.review, .photo])

        // Undo while it is still on the phone: it is simply not sent.
        _ = await quick.undo()
        #expect(quick.state == .undone)
        #expect(box.items.map(\.kind) == [.photo])
    }

    @Test func aNewFountainNearAnotherAsksAndOfflineIsQueued() async throws {
        let defaults = UserDefaults(suiteName: "newfont-\(UUID().uuidString)")!
        let near = #"[{"id":"00000000-0000-0000-0000-0000000000AA","name":"Font del Casal","latitude":41.81205,"longitude":2.09742}]"#
        StubProtocol.responses = ["GET /fonts/near": (200, near), "POST /fonts": (-1, "")]
        let box = outbox(tempDir())
        let model = NewFontModel(draft: NewFontDraft(name: "Font de prova", status: "flowing",
                                                     latitude: 41.81205, longitude: 2.09732),
                                 api: StubProtocol.client(), outbox: box, defaults: defaults)
        model.draft.name = "Font de prova "
        #expect(NewFontDraft.load(defaults) != nil, "a half-filled form is kept")
        await model.submit()
        guard case .confirmDuplicate(let name, let meters) = model.state else {
            Issue.record("expected the duplicate question, got \(model.state)"); return
        }
        #expect(name == "Font del Casal")
        #expect((7...10).contains(meters))
        await model.confirmDistinct()
        #expect(model.state == .queued)
        let item = try #require(box.items.first)
        #expect(item.kind == .font)
        #expect(item.newFont?.name == "Font de prova")
        #expect(item.newFont?.allowNearbyDuplicate == true)
        #expect(item.firstStatus == "flowing")
        #expect(NewFontDraft.load(defaults) == nil, "sending removes the draft")
    }

    @Test func aQueuedPhotoKeepsItsExif() async throws {
        StubProtocol.sent = []
        StubProtocol.responses = [
            "POST /images": (200, #"{"url":"/uploads/x.jpg"}"#),
            "PUT /fonts/\(font.uuidString)/photo": (200, #"{}"#),
        ]
        let box = outbox(tempDir())
        let meta = PhotoMeta(takenAt: Date(timeIntervalSince1970: 1_790_000_000), latitude: 41.81, longitude: 2.09)
        try box.enqueuePhoto(jpeg: Data([0xFF, 0xD8, 0xFF]), meta: meta, fontID: font, fontName: nil)
        #expect(await box.flush() == 1)
        let upload = try #require(StubProtocol.sent.first { $0.path == "/images" }?.body)
        let text = String(decoding: upload, as: UTF8.self)
        #expect(text.contains("name=\"latitude\"\r\n\r\n41.81"))
        #expect(text.contains("name=\"takenAt\""))
    }
}
}

struct MapControlsTests {
    private func font(_ status: String?, drinkable: Drinkable? = nil, source: WaterSource? = nil,
                      confirmations: Int = 0, daysAgo: Double = 1) -> FontSummary {
        FontSummary(id: UUID(), name: nil, latitude: 41.8, longitude: 2.1, image: nil, description: nil,
                    source: source, drinkable: drinkable, country: nil, region: nil, createdAt: nil,
                    lastWaterStatus: status, lastUpdate: status == nil ? nil : Date.now.addingTimeInterval(-86_400 * daysAgo),
                    latestConfirmations: confirmations, recentStatusReporters: 1, recentStatusConflict: false)
    }

    @Test func filtersMatchTheWeb() {
        let flowing = font("flowing", confirmations: 1)
        let dry = font("dry", drinkable: .no)
        let unchecked = font(nil, source: .spring)
        let all = [flowing, dry, unchecked]
        #expect(MapFilters().apply(all).count == 3)
        #expect(MapFilters(onlyWithWater: true).apply(all) == [flowing])
        #expect(MapFilters(onlyReliable: true).apply(all) == [flowing])
        #expect(MapFilters(hideNonPotable: true).apply(all) == [flowing, unchecked])
        #expect(MapFilters(source: .spring).apply(all) == [unchecked])
        #expect(MapFilters(onlyWithWater: true, source: .spring).activeCount == 2)
    }

    @Test func tilesCoveringABox() throws {
        let box = try #require(MapBox(minLat: 41.80, maxLat: 41.82, minLong: 2.09, maxLong: 2.11))
        let tiles = TileKey.covering(box, zoom: 14)
        #expect(!tiles.isEmpty && tiles.count <= 4)
        #expect(tiles.allSatisfy { $0.z == 14 && (8287...8289).contains($0.x) })
        // Each zoom level has four times as many.
        #expect(TileKey.covering(box, zoom: 16).count > tiles.count * 2)
    }

    @Test func webTextsWithoutTheirEmoji() {
        let es = Bundle(path: Bundle.main.path(forResource: "es", ofType: "lproj")!)!
        #expect(L10n.plain("map.onlyWater", bundle: es) == "Solo con agua")
        #expect(L10n.plain("map.addFont", bundle: es) == "Añadir fuente")
    }
}

struct OfflineZoneTests {
    private func font(_ lat: Double, _ lon: Double) -> FontSummary {
        FontSummary(id: UUID(), name: nil, latitude: lat, longitude: lon, image: nil, description: nil, source: nil,
                    drinkable: nil, country: nil, region: nil, createdAt: nil, lastWaterStatus: nil, lastUpdate: nil,
                    latestConfirmations: nil, recentStatusReporters: nil, recentStatusConflict: nil)
    }

    @Test func aZoneAnswersOnlyForWhatItCovers() throws {
        let inside = font(41.81, 2.10)
        let zone = OfflineZone(id: UUID(), name: "Moià", savedAt: .now, minLat: 41.80, maxLat: 41.82,
                               minLong: 2.09, maxLong: 2.11, fonts: [inside], tileLayer: nil, tiles: [],
                               tileBytes: 0, photos: [], photoBytes: 0)
        let view = try #require(MapBox(minLat: 41.805, maxLat: 41.815, minLong: 2.095, maxLong: 2.105))
        #expect(zone.fonts(in: view) == [inside])
        // Far away: nothing, rather than fountains 900 km off sorted as if they were near.
        let cadiz = try #require(MapBox(minLat: 36.5, maxLat: 36.6, minLong: -6.3, maxLong: -6.2))
        #expect(zone.fonts(in: cadiz).isEmpty)
    }

    @Test func theMapPlanIsThisZoomAndTwoMore() throws {
        let box = try #require(MapBox(minLat: 41.80, maxLat: 41.82, minLong: 2.09, maxLong: 2.11))
        let plan = OfflineZones.tilePlan(box: box, zoom: 15.4, layer: .icgc)
        #expect(Set(plan.map(\.z)) == [15, 16, 17])
        // Never past what the layer serves.
        #expect(Set(OfflineZones.tilePlan(box: box, zoom: 17.2, layer: .icgc).map(\.z)) == [17, 18])
    }
}

struct GPXTests {
    private func font(_ lat: Double, _ lon: Double, name: String? = nil) -> FontSummary {
        FontSummary(id: UUID(), name: name, latitude: lat, longitude: lon, image: nil, description: nil, source: nil,
                    drinkable: nil, country: nil, region: nil, createdAt: nil, lastWaterStatus: nil, lastUpdate: nil,
                    latestConfirmations: nil, recentStatusReporters: nil, recentStatusConflict: nil)
    }

    @Test func readsTracksAndRoutesButNotLooseWaypoints() {
        let xml = """
        <?xml version="1.0"?><gpx xmlns="http://www.topografix.com/GPX/1/1">
        <wpt lat="10" lon="-30"><name>home</name></wpt>
        <trk><trkseg><trkpt lat="41.80" lon="2.10"><ele>700.5</ele></trkpt><trkpt lat="41.81" lon="2.10"/></trkseg></trk>
        <rte><rtept lat="41.82" lon="2.10"></rtept></rte>
        <trk><trkseg><trkpt lat="95" lon="2.10"/></trkseg></trk>
        </gpx>
        """
        let points = GPX.read(Data(xml.utf8))
        #expect(points.map(\.latitude) == [41.80, 41.81, 41.82])
        #expect(points.first?.elevation == 700.5)
        #expect(points[1].elevation == nil)
    }

    @Test func aFountainBesideTheRouteIsFoundByLongitude() throws {
        // A north-south route; the fountain is 200 m EAST, so only the cosine of the
        // latitude gets the distance right (at 41.8° a degree of longitude is ~83 km).
        let route = [GPX.Point(latitude: 41.80, longitude: 2.10, elevation: nil),
                     GPX.Point(latitude: 41.84, longitude: 2.10, elevation: nil)]
        let east200 = font(41.82, 2.10 + 200 / 83_000)
        let east400 = font(41.82, 2.10 + 400 / 83_000)
        let found = GPX.fountains([east400, east200], along: route, corridor: 250)
        #expect(found.map(\.font.id) == [east200.id])
        let hit = try #require(found.first)
        #expect((180...220).contains(hit.detour))
        #expect(abs(hit.km - 2.22) < 0.05)
    }

    @Test func theBoxIsWidenedByDefault() throws {
        // A straight east-west route has a box of zero height without the margin.
        let route = [GPX.Point(latitude: 41.8, longitude: 2.0, elevation: nil),
                     GPX.Point(latitude: 41.8, longitude: 2.1, elevation: nil)]
        let box = try #require(GPX.box(of: route))
        #expect(box.maxLat - box.minLat > 0.017)
    }

    @Test func driestCountsBothEnds() {
        #expect(GPX.driest(fountainKms: [3, 4], lengthKm: 10) == GPX.DryStretch(fromKm: 4, toKm: 10))
        #expect(GPX.driest(fountainKms: [6, 7], lengthKm: 8) == GPX.DryStretch(fromKm: 0, toKm: 6))
        #expect(GPX.driest(fountainKms: [], lengthKm: 5) == GPX.DryStretch(fromKm: 0, toKm: 5))
    }

    @Test func writingEscapesWhatWouldBreakTheFile() {
        let gpx = GPX.build([GPX.Waypoint(latitude: 41.8, longitude: 2.1, name: "Font d'en Pep & <Co>\u{0001}",
                                          description: nil)])
        #expect(gpx.contains("<name>Font d&apos;en Pep &amp; &lt;Co&gt;</name>"))
        #expect(gpx.contains("<sym>Drinking Water</sym>"))
        #expect(gpx.contains("lat=\"41.8000000\""))
        let many = (0..<600).map { GPX.Waypoint(latitude: 0, longitude: Double($0) / 1000, name: "x", description: nil) }
        #expect(GPX.build(many).components(separatedBy: "<wpt ").count - 1 == GPX.maxWaypoints)
    }

    @Test func simplifyingKeepsBothEnds() {
        let points = (0...100).map { GPX.Point(latitude: 41.8 + Double($0) * 0.00001, longitude: 2.1, elevation: nil) }
        let simple = GPX.simplified(points)
        #expect(simple.first == points.first && simple.last == points.last)
        #expect(simple.count < 10)
    }
}

struct NewFontPlacementTests {
    let center = CLLocationCoordinate2D(latitude: 41.8105, longitude: 2.0977)

    @Test func thePinStartsWhereThePersonMeans() {
        #expect(NewFontPlacement.start(mapCenter: center, me: nil).latitude == center.latitude)
        // Looking at their own surroundings: the pin starts at them.
        let near = CLLocation(latitude: 41.8110, longitude: 2.0977)
        #expect(NewFontPlacement.start(mapCenter: center, me: near).latitude == near.coordinate.latitude)
        // Looking elsewhere: the centre of the map, not silently back home.
        let far = CLLocation(latitude: 41.8205, longitude: 2.0977)
        #expect(NewFontPlacement.start(mapCenter: center, me: far).latitude == center.latitude)
        #expect(NewFontPlacement.remoteKm(pin: center, me: far).map { ($0 * 10).rounded() / 10 } == 1.1)
        #expect(NewFontPlacement.remoteKm(pin: center, me: near) == nil)
    }
}
