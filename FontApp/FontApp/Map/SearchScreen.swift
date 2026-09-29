import CoreLocation
import MapKit
import SwiftUI

/// What the Search tab asks the map to show. Each request is new, even for the same
/// fountain twice, so the map reacts every time.
struct MapFocus: Equatable {
    enum Target {
        case fountain(FontSummary)
        case place(MKMapRect)
    }

    let id = UUID()
    let target: Target

    static func == (a: MapFocus, b: MapFocus) -> Bool { a.id == b.id }
}

/// The Search tab, as iOS 26 asks: the field lives at the bottom, in the tab bar, where
/// the thumb is, and the system draws, clears and cancels it. On a wide screen the tab bar
/// becomes a sidebar and the field moves to its top, with nothing to do here.
/// Fountains by name from the API, places from MapKit; before typing, what is near.
/// Choosing one goes to the map and shows it there: a fountain is a place to walk to.
struct SearchScreen: View {
    let onShow: (MapFocus.Target) -> Void

    @Environment(LocationService.self) private var location
    @Environment(SessionStore.self) private var session
    @State private var model = SearchModel()
    @State private var recent: [FontSummary] = []
    @State private var isActive = false

    var body: some View {
        NavigationStack {
            List {
                // Before typing, what is near, as Apple Maps does.
                if model.query.trimmingCharacters(in: .whitespaces).count < 2 {
                    recentSection
                    nearbySection
                }
                // A place that is exactly what was typed (a town) goes first; otherwise
                // fountains, which is what the app is for.
                if model.placesFirst {
                    placesSection
                    fountainsSection
                } else {
                    fountainsSection
                    placesSection
                }
                if let error = model.error {
                    Text(error).foregroundStyle(.secondary)
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .overlay {
                if model.isEmptyResult {
                    ContentUnavailableView.search(text: model.query)
                }
            }
            .navigationTitle(L10n.t("ios.search.title"))
            .searchable(text: $model.query, isPresented: $isActive, prompt: L10n.t("ios.search.prompt"))
            .autocorrectionDisabled()
        }
        .onChange(of: model.query) { model.queryChanged(near: location.location) }
        .onChange(of: session.userID, initial: true) { _, user in recent = RecentFountains.list(for: user) }
        // Again once the position arrives: the first fix often comes after the tab opens.
        .task(id: location.location == nil) { await model.loadNearby(from: location.location) }
    }

    /// The keyboard goes, the query stays: coming back to the tab finds the same results.
    private func show(_ target: MapFocus.Target) {
        isActive = false
        onShow(target)
    }

    /// Fountains opened from here, the latest first: looking one up again is common, and
    /// typing its name on a phone is not. Each can be forgotten on its own.
    @ViewBuilder private var recentSection: some View {
        if !recent.isEmpty {
            Section {
                ForEach(recent) { font in
                    HStack {
                        Button {
                            choose(font)
                        } label: {
                            FountainResultRow(font: font, from: location.location)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        // Two buttons in one row: without their own styles the list makes
                        // the whole row one tap, and the ✕ would open the fountain too.
                        .buttonStyle(.plain)
                        Button {
                            withAnimation { recent = RecentFountains.remove(font.id, for: session.userID) }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .tint(.secondary)
                        .accessibilityLabel(L10n.t("ios.search.forget"))
                    }
                }
            } header: {
                HStack {
                    Text(L10n.t("search.recent"))
                    Spacer()
                    Button(L10n.t("search.clearHistory")) {
                        withAnimation { recent = RecentFountains.clear(for: session.userID) }
                    }
                    .font(.footnote)
                    .textCase(nil)
                }
            }
        }
    }

    /// A fountain chosen from the results or the recent ones: remembered, then shown.
    private func choose(_ font: FontSummary) {
        recent = RecentFountains.add(font, for: session.userID)
        show(.fountain(font))
    }

    @ViewBuilder private var nearbySection: some View {
        if location.location == nil {
            EmptyView()
        } else if let nearby = model.nearby {
            Section(L10n.t("map.nearbyTitle")) {
                if nearby.isEmpty {
                    Text(L10n.t("map.nearbyEmpty")).foregroundStyle(.secondary)
                }
                ForEach(nearby) { font in
                    Button {
                        show(.fountain(font))
                    } label: {
                        NearbyRow(font: font, from: location.location)
                    }
                    .foregroundStyle(.primary)
                }
            }
        } else {
            Section(L10n.t("map.nearbyTitle")) { ProgressView() }
        }
    }

    @ViewBuilder private var fountainsSection: some View {
        if !model.fountains.isEmpty {
            Section(L10n.t("ios.search.fountains")) {
                ForEach(model.fountains) { font in
                    Button {
                        choose(font)
                    } label: {
                        FountainResultRow(font: font, from: location.location)
                    }
                    .foregroundStyle(.primary)
                }
            }
        }
    }

    @ViewBuilder private var placesSection: some View {
        if !model.places.isEmpty {
            Section(L10n.t("ios.search.places")) {
                ForEach(model.places, id: \.self) { place in
                    Button {
                        Task {
                            if let rect = await model.rect(for: place) {
                                show(.place(rect))
                            }
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(place.title)
                            if !place.subtitle.isEmpty {
                                Text(place.subtitle).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        .frame(minHeight: 44, alignment: .leading)
                    }
                    .foregroundStyle(.primary)
                }
            }
        }
    }
}

/// A nearby fountain: unlike search results, `/fonts/near` carries the status, so the
/// status and its confidence are shown, with their emojis as on the web.
private struct NearbyRow: View {
    let font: FontSummary
    let from: CLLocation?

    var body: some View {
        HStack(spacing: 12) {
            Text(font.source?.emoji ?? "💧").font(.title2).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.fontName(font.name))
                let level = Confidence.level(of: font.evidence)
                let status = WaterStatus(font.lastWaterStatus).map { "\($0.emoji) \(L10n.t($0.labelKey))" }
                Text([status, "\(level.emoji) \(L10n.t(level.labelKey))"].compactMap { $0 }.joined(separator: " · "))
                    .font(.footnote)
                if let distance {
                    Text(distance).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .frame(minHeight: 44)
    }

    private var distance: String? {
        guard let from else { return nil }
        let meters = from.distance(from: CLLocation(latitude: font.latitude, longitude: font.longitude))
        return Measurement(value: meters, unit: UnitLength.meters).formatted(.measurement(width: .abbreviated, usage: .road))
    }
}

private struct FountainResultRow: View {
    let font: FontSummary
    let from: CLLocation?

    var body: some View {
        HStack(spacing: 12) {
            // Its kind, not a status: `/fonts` does not carry the water status, and showing
            // one would call every result "unchecked".
            Text(font.source?.emoji ?? "💧").font(.title2).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.fontName(font.name))
                // Many fountains share a name; distance and area tell them apart. What is
                // not known is left out, never invented.
                let details = [distance, font.region].compactMap { $0 }
                if !details.isEmpty {
                    Text(details.joined(separator: " · ")).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .frame(minHeight: 44)
    }

    private var distance: String? {
        guard let from else { return nil }
        let meters = from.distance(from: CLLocation(latitude: font.latitude, longitude: font.longitude))
        return Measurement(value: meters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }
}

/// The last fountains opened from Search, per account (and one list signed out), on
/// this phone only, as the web keeps them in the browser.
nonisolated enum RecentFountains {
    static let limit = 5

    private static func key(_ user: UUID?) -> String { "search.recent.v1.\(user?.uuidString ?? "anon")" }

    static func list(for user: UUID?, _ defaults: UserDefaults = .standard) -> [FontSummary] {
        defaults.data(forKey: key(user)).flatMap { try? JSONDecoder().decode([FontSummary].self, from: $0) } ?? []
    }

    @discardableResult
    static func add(_ font: FontSummary, for user: UUID?, _ defaults: UserDefaults = .standard) -> [FontSummary] {
        save(Array(([font] + list(for: user, defaults).filter { $0.id != font.id }).prefix(limit)), for: user, defaults)
    }

    @discardableResult
    static func remove(_ id: UUID, for user: UUID?, _ defaults: UserDefaults = .standard) -> [FontSummary] {
        save(list(for: user, defaults).filter { $0.id != id }, for: user, defaults)
    }

    @discardableResult
    static func clear(for user: UUID?, _ defaults: UserDefaults = .standard) -> [FontSummary] {
        save([], for: user, defaults)
    }

    private static func save(_ fonts: [FontSummary], for user: UUID?, _ defaults: UserDefaults) -> [FontSummary] {
        defaults.set(try? JSONEncoder().encode(fonts), forKey: key(user))
        return fonts
    }
}

@Observable
final class SearchModel: NSObject, MKLocalSearchCompleterDelegate {
    var query = ""
    private(set) var fountains: [FontSummary] = []
    private(set) var places: [MKLocalSearchCompletion] = []
    private(set) var error: String?
    private(set) var searchedQuery = ""
    /// `nil` until loaded.
    private(set) var nearby: [FontSummary]?

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let completer = MKLocalSearchCompleter()
    @ObservationIgnored private var task: Task<Void, Never>?

    init(api: APIClient = .shared) {
        self.api = api
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func loadNearby(from location: CLLocation?) async {
        guard let location, nearby == nil else { return }
        let found = (try? await api.nearby(latitude: location.coordinate.latitude,
                                           longitude: location.coordinate.longitude, quantity: 15))
            ?? OfflineZones.shared.fonts(in: MapBox(minLat: location.coordinate.latitude - 0.03,
                                                    maxLat: location.coordinate.latitude + 0.03,
                                                    minLong: location.coordinate.longitude - 0.04,
                                                    maxLong: location.coordinate.longitude + 0.04)!)
        nearby = Self.sorted(found, from: location)
    }

    var placesFirst: Bool {
        guard let title = places.first?.title else { return false }
        return title.compare(query.trimmingCharacters(in: .whitespaces),
                             options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    var isEmptyResult: Bool {
        !searchedQuery.isEmpty && searchedQuery == query && fountains.isEmpty && places.isEmpty && error == nil
    }

    /// Waits for a pause in typing: every keystroke would be a request.
    func queryChanged(near location: CLLocation?) {
        task?.cancel()
        let term = query.trimmingCharacters(in: .whitespaces)
        guard term.count >= 2 else {
            fountains = []
            places = []
            searchedQuery = ""
            return
        }
        if let location {
            completer.region = MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 100_000,
                                                  longitudinalMeters: 100_000)
        }
        completer.queryFragment = term
        task = Task { [weak self, api] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            do {
                let found = try await api.searchFonts(term)
                guard !Task.isCancelled, let self else { return }
                self.fountains = Self.sorted(found, from: location)
                self.error = nil
                self.searchedQuery = term
            } catch is CancellationError {
            } catch {
                self?.error = ErrorText.describe(error)
            }
        }
    }

    /// Nearest first when the position is known; the server's relevance order otherwise.
    static func sorted(_ fonts: [FontSummary], from location: CLLocation?) -> [FontSummary] {
        guard let location else { return fonts }
        return fonts.sorted {
            location.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))
                < location.distance(from: CLLocation(latitude: $1.latitude, longitude: $1.longitude))
        }
    }

    func rect(for completion: MKLocalSearchCompletion) async -> MKMapRect? {
        let search = MKLocalSearch(request: MKLocalSearch.Request(completion: completion))
        guard let response = try? await search.start() else { return nil }
        return MKMapRect(response.boundingRegion)
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = Array(completer.results.prefix(6))
        Task { @MainActor in self.places = results }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: any Error) {}
}

extension MKMapRect {
    init(_ region: MKCoordinateRegion) {
        let a = MKMapPoint(CLLocationCoordinate2D(latitude: region.center.latitude + region.span.latitudeDelta / 2,
                                                  longitude: region.center.longitude - region.span.longitudeDelta / 2))
        let b = MKMapPoint(CLLocationCoordinate2D(latitude: region.center.latitude - region.span.latitudeDelta / 2,
                                                  longitude: region.center.longitude + region.span.longitudeDelta / 2))
        self.init(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }
}
