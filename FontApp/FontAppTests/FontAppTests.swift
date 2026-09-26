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
                            confirmations: 0, lastConfirmedAt: nil)
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
