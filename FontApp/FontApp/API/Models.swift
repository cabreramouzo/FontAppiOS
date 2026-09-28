import Foundation

// Response shapes of the FontApp API. The contract lives in FontAppBE (`docs/api.md`,
// and the DTOs next to each controller, which win when the two disagree).
// Optional fields are omitted from the JSON when null, so every one is `?` here.

/// Kind of water point (`fonts.source`).
nonisolated enum WaterSource: String, Codable, Sendable {
    case tap, mountain, spring, well, fountain, other
}

/// Declared drinkability (`fonts.drinkable`).
nonisolated enum Drinkable: String, Codable, Sendable {
    case yes, no, conditional, untreated
}

/// A fountain plus the summary of its latest water status, as the map returns it.
nonisolated struct FontSummary: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    /// `nil` for most imported points: show "unnamed fountain", never invent a name.
    let name: String?
    let latitude: Double
    let longitude: Double
    let image: String?
    let description: String?
    let source: WaterSource?
    let drinkable: Drinkable?
    let country: String?
    let region: String?
    let createdAt: Date?
    let lastWaterStatus: String?
    let lastUpdate: Date?
    let latestConfirmations: Int?
    let recentStatusReporters: Int?
    let recentStatusConflict: Bool?

    var evidence: ConfidenceEvidence {
        ConfidenceEvidence(
            lastWaterStatus: lastWaterStatus,
            lastUpdate: lastUpdate,
            latestConfirmations: latestConfirmations ?? 0,
            recentStatusReporters: recentStatusReporters ?? 0,
            recentStatusConflict: recentStatusConflict ?? false
        )
    }
}

/// Server-side aggregate shown when the viewport holds more than 3,000 fountains.
nonisolated struct MapCluster: Codable, Hashable, Sendable {
    let latitude: Double
    let longitude: Double
    let count: Int
}

/// `GET /fonts/map`: either individual fountains or clusters, never both.
nonisolated struct MapResponse: Codable, Sendable {
    let total: Int
    let fonts: [FontSummary]
    let clusters: [MapCluster]
}

/// `GET /fonts/:id`. Not the bare `Font` that `docs/api.md` describes: the server adds
/// `lastWaterStatus`, `lastUpdate`, `statusConflict` and `mayor` (`FontController.FontDetail`).
nonisolated struct FontDetail: Codable, Identifiable, Sendable {
    struct Creator: Codable, Sendable { let id: UUID? }
    var creator: Creator? = nil
    let id: UUID
    let name: String?
    let latitude: Double
    let longitude: Double
    let image: String?
    let description: String?
    let source: WaterSource?
    let drinkable: Drinkable?
    let country: String?
    let region: String?
    let municipality: String?
    let createdAt: Date?
    let retiredAt: Date?
    let lastWaterStatus: String?
    let lastUpdate: Date?
    let statusConflict: Bool?
}

extension FontSummary {
    /// A page as a summary, for opening it from lists that only carry an id.
    nonisolated init(_ d: FontDetail) {
        self.init(id: d.id, name: d.name, latitude: d.latitude, longitude: d.longitude, image: d.image,
                  description: d.description, source: d.source, drinkable: d.drinkable, country: d.country,
                  region: d.region, createdAt: d.createdAt, lastWaterStatus: d.lastWaterStatus,
                  lastUpdate: d.lastUpdate, latestConfirmations: nil, recentStatusReporters: nil,
                  recentStatusConflict: d.statusConflict)
    }
}

extension FontDetail {
    /// What the map pin already knew, for when the full page cannot be loaded (no
    /// signal). Enough to show the status and to review or add a photo, which are the
    /// things one does standing in front of a fountain.
    nonisolated init(summary s: FontSummary) {
        self.init(id: s.id, name: s.name, latitude: s.latitude, longitude: s.longitude, image: s.image,
                  description: s.description, source: s.source, drinkable: s.drinkable, country: s.country,
                  region: s.region, municipality: nil, createdAt: s.createdAt, retiredAt: nil,
                  lastWaterStatus: s.lastWaterStatus, lastUpdate: s.lastUpdate,
                  statusConflict: s.recentStatusConflict)
    }
}

/// A review: a status update with optional text, rating and photo.
nonisolated struct CommentResponse: Codable, Identifiable, Sendable {
    let id: UUID
    let userID: UUID?
    let username: String?
    let body: String
    let rating: Int?
    let waterStatus: String?
    let image: String?
    let createdAt: Date
    let confirmations: Int?
    let lastConfirmedAt: Date?
    /// Whether the signed-in user already said "still the same" on it.
    let confirmedByMe: Bool?
    /// The server turned a quick review into a "still the same" on this, someone else's
    /// recent report (`confirmIfUnchanged`). Undoing means taking the confirmation back.
    let confirmedInstead: Bool?
}

/// A comment or an incident ("the tap is broken") about a fountain.
nonisolated struct ReportResponse: Codable, Identifiable, Sendable {
    let id: UUID
    let username: String?
    let message: String
    let isIncident: Bool?
    let incidentKind: String?
    let createdAt: Date
    let parentID: UUID?
    let resolvedAt: Date?
    let resolvedBy: String?
}

/// One entry of `GET /activity`.
nonisolated struct ActivityItem: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case fontAdded, review, report, edit
        /// A kind this build does not know yet. Without it, one new kind on the server
        /// would fail the whole feed.
        case other

        init(from decoder: any Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Kind(rawValue: raw) ?? .other
        }
    }

    let kind: Kind
    let fontID: UUID
    let fontName: String?
    let region: String?
    let author: String?
    let waterStatus: String?
    let text: String?
    let image: String?
    let createdAt: Date
    /// Pagination cursor (epoch seconds, full precision). `createdAt` is truncated to the
    /// second, so it cannot page within one second.
    let cursor: Double
}

/// Account roles, lowest to highest. Unknown roles count as `user`.
nonisolated enum UserRole: String, Codable, Sendable, Comparable {
    case user, moderator, admin, owner

    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = UserRole(rawValue: raw) ?? .user
    }

    private var rank: Int {
        switch self {
        case .user: 0
        case .moderator: 1
        case .admin: 2
        case .owner: 3
        }
    }

    static func < (a: UserRole, b: UserRole) -> Bool { a.rank < b.rank }

    /// Moderator and above see the contribution controls in staff purple, so they do not
    /// contribute as staff by mistake.
    var isStaff: Bool { self >= .moderator }
}

/// The account, as `/auth/login` and `/auth/me` return it for its owner.
nonisolated struct UserResponse: Codable, Equatable, Sendable {
    let id: UUID
    let name: String
    let username: String
    let role: UserRole?
    var isAdmin: Bool? = nil

    var canManageFonts: Bool { role.map { $0 >= .admin } ?? (isAdmin == true) }
}

nonisolated struct LoginResponse: Codable, Sendable {
    let token: String
    let user: UserResponse
}

/// A review as the app sends it: the quick chips send only a status.
nonisolated struct NewReview: Codable, Equatable, Sendable {
    let waterStatus: String
    /// "If this adds nothing, count it as still the same." The server decides.
    let confirmIfUnchanged: Bool
    /// Only when clearly more than a kilometre away; see `RemoteReview`.
    let remoteDistanceM: Int?
}

/// What survives of a photo's EXIF after it is re-encoded for upload.
nonisolated struct PhotoMeta: Codable, Equatable, Sendable {
    var takenAt: Date?
    var latitude: Double?
    var longitude: Double?
}

/// A new fountain as the app sends it (`CreateFontDTO`).
nonisolated struct NewFont: Codable, Equatable, Sendable {
    /// `nil` when there is no proper name: the reader's "unnamed fountain" is not a name.
    var name: String?
    var latitude: Double
    var longitude: Double
    var image: String?
    var description: String?
    var source: WaterSource?
    var drinkable: Drinkable?
    /// Explicit confirmation after being shown a fountain within 25 m.
    var allowNearbyDuplicate: Bool?
}

/// A stop of a proposed round (`GET /missions`).
nonisolated struct MissionTarget: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String?
    let latitude: Double
    let longitude: Double
    let distanceKm: Double
    /// Last check, or `nil` if nobody has ever been.
    let lastCheck: Date?
}

/// Two rounds around a point, ordered by distance and not by drops, not overlapping.
nonisolated struct Missions: Codable, Sendable {
    let km: Double
    /// Fountains without any photo.
    let photoless: [MissionTarget]
    /// Not checked for over half a year.
    let stale: [MissionTarget]
}

/// A new account as `POST /users` takes it.
nonisolated struct NewAccount: Encodable, Equatable, Sendable {
    let name: String
    let username: String
    let email: String
    let password: String
    /// Language of the welcome email (the web's codes: ca, es, gl, eu, en, fr, pt, it).
    let lang: String?
}
