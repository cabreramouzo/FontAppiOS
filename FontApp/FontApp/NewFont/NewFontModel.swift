import CoreLocation
import Foundation
import Observation

/// Where a new fountain's pin starts. Port of `web/src/lib/newFontPlacement.ts`: the map
/// says what the person means. Looking at their own surroundings (map centre within
/// 250 m), the pin starts at them; looking elsewhere, at the centre of the map, not
/// silently back where they stand.
nonisolated enum NewFontPlacement {
    static let nearbyMeters: Double = 250
    /// Closer than this to an existing fountain, the app names it and asks.
    static let duplicateMeters: Double = 25

    static func start(mapCenter: CLLocationCoordinate2D, me: CLLocation?) -> CLLocationCoordinate2D {
        guard let me else { return mapCenter }
        let center = CLLocation(latitude: mapCenter.latitude, longitude: mapCenter.longitude)
        return me.distance(from: center) > nearbyMeters ? mapCenter : me.coordinate
    }

    /// Kilometres from the person to the pin, when it is clearly elsewhere.
    static func remoteKm(pin: CLLocationCoordinate2D, me: CLLocation?) -> Double? {
        guard let me else { return nil }
        let d = me.distance(from: CLLocation(latitude: pin.latitude, longitude: pin.longitude))
        return d > nearbyMeters ? d / 1000 : nil
    }
}

/// A half-filled new fountain. It survives the app being killed; closing the form keeps
/// it, sending or an explicit discard removes it (product rule). The photo is not kept:
/// it would be megabytes in the defaults, and the form says to choose it again.
nonisolated struct NewFontDraft: Codable, Equatable, Sendable {
    var name = ""
    var description = ""
    var source: WaterSource?
    var drinkable: Drinkable?
    var status: WaterStatus.RawValue?
    var latitude: Double
    var longitude: Double

    var isEmpty: Bool {
        name.isEmpty && description.isEmpty && source == nil && drinkable == nil && status == nil
    }

    private static let key = "draft.newFont"

    static func load(_ defaults: UserDefaults = .standard) -> NewFontDraft? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(NewFontDraft.self, from: $0) }
    }

    func save(_ defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(self), forKey: Self.key)
    }

    static func clear(_ defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}

@Observable
final class NewFontModel {
    enum State: Equatable {
        case editing
        case checking
        /// A fountain within 25 m: named, with its distance, so the question can be
        /// answered — the case that led to this was 3 m away and under another name.
        case confirmDuplicate(name: String, meters: Int)
        case sending
        case created
        case queued
        case failed(String)
    }

    var draft: NewFontDraft {
        didSet { if draft != oldValue { draft.save(defaults) } }
    }
    var photo: PhotoPreparer.Prepared?
    /// New accounts may add a few fountains a day; past that, one can ask for an exception.
    private(set) var limitReached = false
    private(set) var state: State = .editing

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let outbox: Outbox
    @ObservationIgnored private let defaults: UserDefaults

    init(draft: NewFontDraft, api: APIClient = .shared, outbox: Outbox = .shared, defaults: UserDefaults = .standard) {
        self.draft = draft
        self.api = api
        self.outbox = outbox
        self.defaults = defaults
    }

    var pin: CLLocationCoordinate2D {
        get { CLLocationCoordinate2D(latitude: draft.latitude, longitude: draft.longitude) }
        set {
            draft.latitude = newValue.latitude
            draft.longitude = newValue.longitude
        }
    }

    /// The photo's own GPS, offered as the position when it differs from the pin.
    var photoPosition: CLLocationCoordinate2D? {
        guard let lat = photo?.meta.latitude, let lon = photo?.meta.longitude else { return nil }
        let there = CLLocation(latitude: lat, longitude: lon)
        guard there.distance(from: CLLocation(latitude: draft.latitude, longitude: draft.longitude)) > 5 else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    func submit() async {
        state = .checking
        if let nearest = await nearestExisting() {
            state = .confirmDuplicate(name: L10n.fontName(nearest.font.name), meters: nearest.meters)
            return
        }
        await send(allowNearbyDuplicate: false)
    }

    func confirmDistinct() async { await send(allowNearbyDuplicate: true) }

    func cancelDuplicate() { state = .editing }

    /// Deleted on purpose: the draft goes too.
    func discard() {
        NewFontDraft.clear(defaults)
    }

    private func nearestExisting() async -> (font: FontSummary, meters: Int)? {
        // Best effort: the server repeats the check with authority when creating.
        guard let near = try? await api.nearby(latitude: draft.latitude, longitude: draft.longitude) else { return nil }
        let pin = CLLocation(latitude: draft.latitude, longitude: draft.longitude)
        return near
            .map { ($0, pin.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))) }
            .filter { $0.1 <= NewFontPlacement.duplicateMeters }
            .min { $0.1 < $1.1 }
            .map { ($0.0, Int($0.1.rounded())) }
    }

    private func send(allowNearbyDuplicate: Bool) async {
        state = .sending
        let trimmed = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = draft.description.trimmingCharacters(in: .whitespacesAndNewlines)
        var font = NewFont(name: trimmed.isEmpty ? nil : trimmed, latitude: draft.latitude, longitude: draft.longitude,
                           image: nil, description: description.isEmpty ? nil : description,
                           source: draft.source, drinkable: draft.drinkable,
                           allowNearbyDuplicate: allowNearbyDuplicate ? true : nil)
        do {
            if let photo {
                font.image = try await api.uploadImage(photo.jpeg, meta: photo.meta)
            }
            let created = try await api.createFont(font)
            // The status is the fountain's first update. If it fails the fountain exists
            // anyway; it can be reviewed afterwards.
            if let status = draft.status { try? await api.postStatus(on: created.id, status) }
            NewFontDraft.clear(defaults)
            state = .created
            NotificationCenter.default.post(name: .fontChanged, object: created.id)
        } catch let error as APIError where error.status == 0 {
            // No signal: the fountain is not lost. It waits on the phone with its photo.
            do {
                font.image = nil
                try outbox.enqueueFont(font, firstStatus: draft.status, jpeg: photo?.jpeg, meta: photo?.meta)
                NewFontDraft.clear(defaults)
                state = .queued
            } catch {
                state = .failed(ErrorText.describe(error))
            }
        } catch {
            limitReached = (error as? APIError)?.code == "font.newAccountLimit"
            state = .failed(ErrorText.describe(error))
        }
    }
}
