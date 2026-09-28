import Foundation

// Response shapes of the FontApp API. The contract lives in FontAppBE (`docs/api.md`,
// and the DTOs next to each controller, which win when the two disagree).
// Optional fields are omitted from the JSON when null, so every one is `?` here.

/// Kind of water point (`fonts.source`).
nonisolated enum WaterSource: String, Codable, Sendable {
    case tap, mountain, spring, well, fountain, other

    /// Fixed per kind, as `SOURCE_EMOJI` in `web/src/lib/waterType.ts`.
    var emoji: String {
        switch self {
        case .tap: "🚰"
        case .mountain: "⛰️"
        case .spring: "💦"
        case .well: "🪣"
        case .fountain: "⛲"
        case .other: "💧"
        }
    }
}

/// Declared drinkability (`fonts.drinkable`).
nonisolated enum Drinkable: String, Codable, Sendable {
    case yes, no, conditional, untreated

    /// The web's (`DRINKABLE_EMOJI`): untreated is a drop, not a warning — no verdict.
    var emoji: String {
        switch self {
        case .yes: "✅"
        case .no: "🚱"
        case .conditional: "⚠️"
        case .untreated: "💧"
        }
    }
}

extension WaterSource {
    /// "🚰 Urban tap (mains)", as the web writes a kind wherever it names one.
    var emojiLabel: String { "\(emoji) \(L10n.t("source.\(rawValue)"))" }
}

extension Drinkable {
    var emojiLabel: String { "\(emoji) \(L10n.t("drink.\(rawValue)"))" }
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
    /// Spain only; elsewhere `nil`, and a list falls back to `region` — never invents one.
    var municipality: String? = nil

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
    /// Who checked it most in the last 60 days; reconquerable, unlike the pioneer.
    struct Mayor: Codable, Sendable { let userID: UUID?; let username: String; let reviews: Int }
    var creator: Creator? = nil
    var mayor: Mayor? = nil
    /// Hidden from the map, and why: marked as a copy of this one, retired (gone), or
    /// held by moderation (`pending`, `hidden`). Said to everyone who reaches the page.
    var duplicateOf: UUID? = nil
    var moderationState: String? = nil
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

/// A full review from the page: any of status, rating, text and photo (`NewComment`).
nonisolated struct ComposedReview: Codable, Equatable, Sendable {
    var waterStatus: String?
    var rating: Int?
    var body: String?
    var image: String?
}

/// A comment, an incident ("the tap is broken"), or a reply to one (`parentID`).
nonisolated struct NewReport: Encodable, Sendable {
    let message: String
    let isIncident: Bool
    let incidentKind: String?
    let parentID: UUID?
}

/// A photo or document of a fountain's gallery, besides its cover (`GET /fonts/:id/photos`).
nonisolated struct FontPhoto: Codable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable, CaseIterable { case fountain, document, context }
    struct Uploader: Codable, Sendable { let id: UUID?; let username: String? }
    let id: UUID
    let url: String
    let kind: Kind
    let caption: String?
    let createdAt: Date?
    let uploader: Uploader?
}

/// Whether you may ask to take down the cover you put, and whether you still can undo it.
nonisolated struct PhotoRemovalStatus: Codable, Sendable {
    let canRequest: Bool
    let pending: Bool
    let canUndo: Bool
}

/// One change to a fountain's details (`GET /fonts/:id/history`).
nonisolated struct FontEditEntry: Codable, Identifiable, Sendable {
    struct Snapshot: Codable, Sendable {
        let name: String?
        let description: String?
        let source: String?
        let drinkable: String?
    }
    let id: UUID
    let editorName: String?
    let before: Snapshot
    let after: Snapshot
    let createdAt: Date
}

/// `GET /fonts/:id/nearest-water`.
nonisolated struct NearestWater: Codable, Identifiable, Sendable {
    let id: UUID
    let name: String?
    let source: WaterSource?
    let latitude: Double
    let longitude: Double
    let distanceKm: Double
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
    var userID: UUID? = nil
    let username: String?
    let message: String
    let isIncident: Bool?
    let incidentKind: String?
    let createdAt: Date
    let parentID: UUID?
    let resolvedAt: Date?
    let resolvedBy: String?
    var editedAt: Date? = nil
    var likes: Int? = nil
    var likedByMe: Bool? = nil
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
    /// Only in your own responses (login, `/auth/me`, editing), like the settings below.
    var email: String? = nil
    var namePublic: Bool? = nil
    var emailPublic: Bool? = nil
    var weeklyDigest: Bool? = nil
    var mentionEmails: Bool? = nil
    var gamificationOptOut: Bool? = nil

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

/// A notice in the in-app bell (`GET /notifications`). `excerpt` is often a code, not a
/// sentence (`review:dry`, `7|6|142`): the server does not know the reader's language.
nonisolated struct NotificationItem: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let kind: String
    let actorName: String
    /// `nil` when the fountain was deleted: the notice stays, but no longer links.
    let fontID: UUID?
    let fontName: String?
    let excerpt: String
    let read: Bool
    let createdAt: Date?
}

nonisolated struct NotificationInbox: Codable, Sendable {
    let unread: Int
    let items: [NotificationItem]
}

/// A review of yours (`GET /auth/me/comments`): where, what you said and when.
nonisolated struct MyComment: Codable, Identifiable, Sendable {
    let id: UUID
    let fontID: UUID
    let fontName: String?
    let body: String
    let waterStatus: String?
    let createdAt: Date?
}

/// Your score (`GET /gamification/me`), only the part the profile shows. `nil` (a 204)
/// when you switched the game off. Level keys (`river`) are translated here, never shown.
nonisolated struct GamificationSummary: Decodable, Sendable {
    struct Impact: Decodable, Sendable {
        let fontsWithPhotoThanksToYou: Int
        let fontsYouKeepFresh: Int
        let fontsYouPutOnTheMap: Int
    }

    let gotes: Int
    /// Contributed but still inside the 72 h window.
    let pending: Int
    let level: String
    let nextLevel: String?
    let gotesToNextLevel: Int?
    /// The level you reach once the pending drops settle, when it is higher.
    let pendingLevel: String?
    let impact: Impact
    /// Fountains you are the guardian of (who checks them most in 60 days).
    let mayorCount: Int?
    let provisional: Bool
    /// What your level opens (phase 6): `markDuplicate`, `resolveIncident`…
    struct Grant: Decodable, Sendable { let capabilities: [String] }
    var grant: Grant? = nil
    /// The ladder of levels, the badge families with their progress, and the specials.
    var levels: [LevelStanding]? = nil
    var collection: [BadgeSlot]? = nil
    var special: [SpecialStanding]? = nil
}

nonisolated struct LevelStanding: Decodable, Identifiable, Sendable {
    let key: String
    let from: Int
    let reached: Bool
    let current: Bool
    var id: String { key }
}

/// One badge family: the tier you have (`nil` if none yet) and how far to the next.
nonisolated struct BadgeSlot: Decodable, Identifiable, Sendable {
    let family: String
    let tier: String?
    let progress: Int
    let threshold: Int
    let thresholds: [Int]
    /// The tier you will have once the pending contributions settle, when it is better.
    let pendingTier: String?
    var id: String { family }
    var maxed: Bool { progress >= (thresholds.last ?? .max) }
}

/// A special badge: no progress, you have it or not; some have a limited number of places.
nonisolated struct SpecialStanding: Decodable, Identifiable, Sendable {
    let key: String
    let earnedAt: Date?
    let remaining: Int?
    var id: String { key }
}

/// What you have earned, counting what is still settling (`/gamification/badges/preview`).
nonisolated struct BadgesPreview: Decodable, Sendable {
    struct Badge: Decodable, Hashable, Sendable { let family: String; let tier: String }
    var badges: [Badge]? = nil
    var level: String? = nil
}

/// A fountain whose latest review is yours (`GET /gamification/guarded`), the most
/// forgotten first.
nonisolated struct GuardedFont: Decodable, Identifiable, Sendable {
    let fontID: UUID
    let name: String?
    let days: Int
    /// Past the 90-day cut.
    let stale: Bool
    let source: WaterSource?
    /// What you said last time: that is what goes stale.
    let waterStatus: String?

    var id: UUID { fontID }
}

/// The collection (`GET /gamification/collection`): distinct fountains you reviewed and
/// the kinds you have. `local` only when coordinates were sent and there are fountains around.
nonisolated struct VisitedCollection: Decodable, Sendable {
    struct Kind: Decodable, Sendable {
        let source: String
        let count: Int
    }

    struct Local: Decodable, Sendable {
        let nearby: Int
        let visited: Int
        let radiusKm: Double
    }

    let visited: Int
    let types: [Kind]
    let local: Local?
}

/// `PUT /users/:id`. Name, username and email always travel; each setting only when it
/// changes, since the server leaves an absent one as it was.
nonisolated struct ProfileUpdate: Encodable, Sendable {
    var name: String
    var username: String
    var email: String
    var namePublic: Bool?
    var emailPublic: Bool?
    var weeklyDigest: Bool?
    var mentionEmails: Bool?
    var gamificationOptOut: Bool?

    init(_ user: UserResponse) {
        name = user.name
        username = user.username
        email = user.email ?? ""
    }
}

/// The EXIF kept apart when a photo was uploaded (re-encoding strips it).
nonisolated struct PhotoExif: Decodable, Sendable {
    let photoID: String
    let takenAt: Date?
    let uploadedAt: Date?
    let latitude: Double?
    let longitude: Double?

    /// The photo's id is its file name: `/uploads/<uuid>.jpg`.
    static func id(of url: String) -> String? {
        let name = url.split(separator: "/").last.map(String.init) ?? ""
        let stem = name.split(separator: ".").first.map(String.init) ?? ""
        return UUID(uuidString: stem) == nil ? nil : stem.lowercased()
    }
}
