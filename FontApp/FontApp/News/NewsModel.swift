import CoreLocation
import Foundation
import Observation

/// The `/activity` feed, near the user or everywhere.
@Observable
final class NewsModel {
    enum Scope: Hashable {
        case near
        case everywhere
    }

    enum State {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    /// Radii offered for "near me", in km. Same choice as the web; 5 km by default,
    /// which is what "near" really means in a town.
    static let radii: [Double] = [5, 10, 25, 50]
    static let pageSize = 24
    // API country identifiers, in the same order as the PWA countries.ts.
    static let countries = ["Italy", "Spain", "United States of America", "France", "Germany", "Hungary", "Switzerland", "Japan", "Austria", "Canada", "Bulgaria", "Portugal", "Greece", "Slovakia", "United Kingdom", "Czech Republic", "Romania", "Montenegro", "Netherlands", "Poland", "Republic of Serbia", "Denmark", "Slovenia", "Ireland", "Croatia", "Bosnia and Herzegovina", "Brazil", "Sweden", "Belgium", "Norway", "Finland", "Macedonia", "Argentina", "Albania", "Mexico", "Peru", "Cyprus", "Latvia", "Lithuania", "Ecuador", "Colombia", "Chile", "Kosovo", "Estonia", "Luxembourg", "Iceland", "Cuba", "Bolivia", "Andorra", "Costa Rica", "Liechtenstein", "Uruguay", "Venezuela", "Paraguay", "Nicaragua", "Panama", "Guatemala", "Dominican Republic", "San Marino", "Honduras", "Monaco", "Malta", "Puerto Rico", "El Salvador"]
    static let allCountries = "*"

    /// Remembered between launches, as the web does: someone who chose "everywhere"
    /// should not find "near me" again every time.
    var scope: Scope {
        didSet { defaults.set(scope == .near, forKey: Self.nearKey) }
    }
    var km: Double {
        didSet { defaults.set(km, forKey: Self.kmKey) }
    }
    var country: String {
        didSet { defaults.set(country, forKey: Self.countryKey) }
    }
    private(set) var items: [ActivityItem] = []
    /// The level race above the feed. `nil` until loaded, and kept on failure: it is an
    /// extra over the feed, so an error never shows.
    private(set) var pulse: PulseSnapshot?
    private(set) var state: State = .idle
    private(set) var canLoadMore = false
    private(set) var isLoadingMore = false

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let defaults: UserDefaults
    private static let nearKey = "news.near"
    private static let kmKey = "news.km"
    private static let countryKey = "zones.country"
    @ObservationIgnored private var generation = 0
    /// Where the current list was asked for. A new GPS fix does not reload the feed
    /// (the limit is 120/h), only a change of scope or radius, or pull to refresh.
    @ObservationIgnored private var origin: CLLocationCoordinate2D?

    init(api: APIClient = .shared, defaults: UserDefaults = .standard) {
        self.api = api
        self.defaults = defaults
        // Near me by default; a saved radius only if it is still one of the choices.
        scope = (defaults.object(forKey: Self.nearKey) as? Bool ?? true) ? .near : .everywhere
        let saved = defaults.double(forKey: Self.kmKey)
        km = Self.radii.contains(saved) ? saved : 5
        let savedCountry = defaults.string(forKey: Self.countryKey) ?? Self.allCountries
        country = Self.countries.contains(savedCountry) ? savedCountry : Self.allCountries
    }

    /// The scope actually used: "near" needs a position.
    func effectiveScope(location: CLLocation?) -> Scope {
        scope == .near && location != nil ? .near : .everywhere
    }

    func reload(location: CLLocation?) async {
        generation += 1
        let requestGeneration = generation
        items = []
        canLoadMore = false
        state = .loading
        origin = effectiveScope(location: location) == .near ? location?.coordinate : nil
        do {
            let page = try await fetch(before: nil)
            guard requestGeneration == generation, !Task.isCancelled else { return }
            items = page
            canLoadMore = page.count >= Self.pageSize
            state = .loaded
        } catch is CancellationError {
            return
        } catch {
            guard requestGeneration == generation, !Task.isCancelled else { return }
            state = .failed(ErrorText.describe(error))
        }
    }

    func loadMore() async {
        guard canLoadMore, !isLoadingMore, let before = items.map(\.cursor).min() else { return }
        let requestGeneration = generation
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await fetch(before: before)
            guard requestGeneration == generation, !Task.isCancelled else { return }
            let known = Set(items.map(\.cursor))
            let fresh = page.filter { !known.contains($0.cursor) }
            items += fresh
            // Fewer than a page, or a page with nothing new: the end.
            canLoadMore = page.count >= Self.pageSize && !fresh.isEmpty
        } catch {
            guard requestGeneration == generation else { return }
            canLoadMore = false
        }
    }

    func reloadPulse() async {
        if let fresh = try? await api.pulse() { pulse = fresh }
    }

    private func fetch(before: Double?) async throws -> [ActivityItem] {
        let near = origin.map { (latitude: $0.latitude, longitude: $0.longitude) }
        return try await api.activity(limit: Self.pageSize, near: near, km: near == nil ? nil : km,
                                      country: near == nil && country != Self.allCountries ? country : nil,
                                      before: before)
    }
}
