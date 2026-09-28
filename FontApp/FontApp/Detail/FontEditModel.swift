import CoreLocation
import Foundation
import Observation

/// Only grants issued by the backend count; levels alone do not imply permissions.
nonisolated struct FontEditGrant: Decodable, Sendable {
    let capabilities: [String]
    let blockedBy: [String]
    var activeDays: Int? = nil
    var requiredActiveDays: Int? = nil
}

nonisolated struct FontEditPermissions {
    let canEdit: Bool
    let canRelocate: Bool
    let canSetPhoto: Bool

    init(user: UserResponse?, font: FontDetail, grant: FontEditGrant?) {
        let restricted = grant?.blockedBy.contains("restricted") == true
        canEdit = user != nil && !restricted
        let manages = user.map { $0.canManageFonts || font.creator?.id == $0.id } ?? false
        canRelocate = canEdit && (manages || grant?.capabilities.contains("relocateAnyFont") == true)
        canSetPhoto = canEdit && (manages || font.image == nil)
    }
}

/// Store the baseline too: restoring a draft must not overwrite fields edited by someone
/// else since it was started. Only fields changed relative to this baseline are applied.
nonisolated struct FontEditFields: Codable, Equatable {
    var name: String
    var description: String
    var source: WaterSource?
    var drinkable: Drinkable?
    var latitude: Double
    var longitude: Double

    init(_ font: FontDetail) {
        name = font.name ?? ""
        description = font.description ?? ""
        source = font.source
        drinkable = font.drinkable
        latitude = font.latitude
        longitude = font.longitude
    }

    func payload(baseline: Self, current: FontDetail, permissions: FontEditPermissions,
                 image: String?) -> NewFont {
        let currentFields = Self(current)
        let name = (name != baseline.name ? name : currentFields.name).trimmingCharacters(in: .whitespacesAndNewlines)
        let description = description != baseline.description ? description : currentFields.description
        let moved = latitude != baseline.latitude || longitude != baseline.longitude
        return NewFont(name: name.isEmpty ? nil : name,
                       latitude: permissions.canRelocate && moved ? latitude : current.latitude,
                       longitude: permissions.canRelocate && moved ? longitude : current.longitude,
                       image: permissions.canSetPhoto ? (image ?? current.image) : current.image,
                       description: description.isEmpty ? nil : description,
                       source: source != baseline.source ? source : current.source,
                       drinkable: drinkable != baseline.drinkable ? drinkable : current.drinkable)
    }
}

nonisolated struct FontEditDraft: Codable {
    var baseline: FontEditFields
    var fields: FontEditFields
    var hadPhoto: Bool
    var savedAt: Date

    static func key(origin: URL, userID: UUID, fontID: UUID) -> String {
        "draft.edit.\(origin.absoluteString).\(userID).\(fontID)"
    }

    static func load(key: String, defaults: UserDefaults, now: Date = .now) -> Self? {
        guard let data = defaults.data(forKey: key),
              let draft = try? JSONDecoder().decode(Self.self, from: data),
              now.timeIntervalSince(draft.savedAt) < 7 * 86_400 else { return nil }
        return draft
    }
}

@Observable
final class FontEditModel: Identifiable {
    var id: UUID { fontID }
    let fontID: UUID
    let userID: UUID
    var fields: FontEditFields { didSet { persist() } }
    var photo: PhotoPreparer.Prepared? { didSet { needsPhotoAgain = false; persist() } }
    private(set) var needsPhotoAgain = false
    private(set) var permissions: FontEditPermissions
    private(set) var ready = false
    private(set) var saving = false
    private(set) var error: String?
    private(set) var relocationNotice: String?
    private(set) var original: FontDetail

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let draftKey: String
    @ObservationIgnored private let token: String?
    @ObservationIgnored private var baseline: FontEditFields
    @ObservationIgnored private var uploadedImage: String?

    init(font: FontDetail, userID: UUID, api: APIClient = .shared, defaults: UserDefaults = .standard) {
        self.fontID = font.id
        self.userID = userID
        self.api = api
        self.defaults = defaults
        token = api.credentials.current
        original = font
        draftKey = FontEditDraft.key(origin: api.baseURL, userID: userID, fontID: font.id)
        let restored = FontEditDraft.load(key: draftKey, defaults: defaults)
        baseline = restored?.baseline ?? FontEditFields(font)
        fields = restored?.fields ?? FontEditFields(font)
        needsPhotoAgain = restored?.hadPhoto ?? false
        permissions = FontEditPermissions(user: nil, font: font, grant: nil)
    }

    var dirty: Bool { fields != baseline || photo != nil || needsPhotoAgain }
    var hasRelocation: Bool { fields.latitude != baseline.latitude || fields.longitude != baseline.longitude }

    func undoRelocation() {
        fields.latitude = baseline.latitude
        fields.longitude = baseline.longitude
    }
    var pin: CLLocationCoordinate2D {
        get { .init(latitude: fields.latitude, longitude: fields.longitude) }
        set { fields.latitude = newValue.latitude; fields.longitude = newValue.longitude }
    }
    var movedMeters: Double {
        CLLocation(latitude: fields.latitude, longitude: fields.longitude)
            .distance(from: CLLocation(latitude: original.latitude, longitude: original.longitude))
    }

    func prepare() async {
        ready = false
        error = nil
        do {
            try await refreshPermissions()
            ready = true
        } catch { self.error = ErrorText.describe(error) }
    }

    private func checkAccount() throws {
        guard let token, token == api.credentials.current else {
            throw APIError(status: 401, reason: nil, code: nil, retryAfter: nil)
        }
    }

    private func refreshPermissions() async throws {
        try checkAccount()
        let user = try await api.me()
        guard user.id == userID else { throw APIError(status: 401, reason: nil, code: nil, retryAfter: nil) }
        let current = try await api.font(fontID)
        // Basic wiki editing and ownership do not depend on gamification availability.
        // A failed grant lookup never opens relocation; the write still enforces bans.
        let grant = try? await api.fontEditGrant()
        try checkAccount()
        original = current
        permissions = FontEditPermissions(user: user, font: current, grant: grant)
        relocationNotice = nil
        if !permissions.canRelocate, let grant {
            let blockers = grant.blockedBy
            if blockers.contains("restricted") { relocationNotice = L10n.t("cap.blocked.restricted") }
            else if blockers.contains("optedOut") { relocationNotice = L10n.t("cap.blocked.optedOut") }
            else if blockers.contains("disabled") || blockers.contains("provisional") { relocationNotice = L10n.t("cap.blocked.unavailable") }
            else if blockers.contains("recentlyVoided") { relocationNotice = L10n.t("cap.blocked.recentlyVoided") }
            else if blockers.contains("activeDays"), let have = grant.activeDays, let need = grant.requiredActiveDays {
                relocationNotice = L10n.t("cap.blocked.activeDays", ["have": have, "need": need])
            }
        }
    }

    func usePhoto(_ data: Data, cameraMeta: PhotoMeta? = nil) async {
        do {
            let prepared = try await Task.detached(priority: .userInitiated) { try PhotoPreparer.prepare(data) }.value
            photo = PhotoPreparer.Prepared(jpeg: prepared.jpeg, meta: cameraMeta ?? prepared.meta)
            uploadedImage = nil
        } catch { self.error = L10n.t("photo.failed") }
    }

    func discard() { defaults.removeObject(forKey: draftKey) }

    private func persist() {
        if !dirty { discard(); return }
        let draft = FontEditDraft(baseline: baseline, fields: fields,
                                  hadPhoto: photo != nil || needsPhotoAgain, savedAt: .now)
        defaults.set(try? JSONEncoder().encode(draft), forKey: draftKey)
    }

    /// Edits stay as drafts on failure; replaying a stale whole-fountain PUT from an
    /// offline queue would overwrite later corrections. The PWA also saves edits online.
    func save() async -> FontDetail? {
        guard !saving, dirty else { return nil }
        saving = true
        error = nil
        defer { saving = false }
        do {
            try await refreshPermissions()
            guard permissions.canEdit else {
                throw APIError(status: 403, reason: nil, code: "user.postingRestricted", retryAfter: nil)
            }
            if !permissions.canRelocate,
               (fields.latitude != baseline.latitude || fields.longitude != baseline.longitude) {
                throw APIError(status: 403, reason: nil, code: "capability.relocateAnyFont", retryAfter: nil)
            }
            if photo != nil && !permissions.canSetPhoto {
                throw APIError(status: 403, reason: nil, code: "font.ownerOnly", retryAfter: nil)
            }
            if let photo, uploadedImage == nil {
                try checkAccount()
                uploadedImage = try await api.uploadImage(photo.jpeg, meta: photo.meta, token: token)
            }
            try checkAccount()
            let payload = fields.payload(baseline: baseline, current: original,
                                         permissions: permissions, image: photo == nil ? nil : uploadedImage)
            let updated = try await api.updateFont(fontID, payload, token: token!)
            discard()
            NotificationCenter.default.post(name: .fontChanged, object: fontID)
            return updated
        } catch {
            self.error = ErrorText.describe(error)
            return nil
        }
    }
}
