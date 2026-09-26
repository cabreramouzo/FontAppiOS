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

    var scope: Scope = .near
    var km: Double = 5
    private(set) var items: [ActivityItem] = []
    private(set) var state: State = .idle
    private(set) var canLoadMore = false
    private(set) var isLoadingMore = false

    @ObservationIgnored private let api: APIClient
    /// Where the current list was asked for. A new GPS fix does not reload the feed
    /// (the limit is 120/h), only a change of scope or radius, or pull to refresh.
    @ObservationIgnored private var origin: CLLocationCoordinate2D?

    init(api: APIClient = .shared) {
        self.api = api
    }

    /// The scope actually used: "near" needs a position.
    func effectiveScope(location: CLLocation?) -> Scope {
        scope == .near && location != nil ? .near : .everywhere
    }

    func reload(location: CLLocation?) async {
        state = .loading
        origin = effectiveScope(location: location) == .near ? location?.coordinate : nil
        do {
            let page = try await fetch(before: nil)
            items = page
            canLoadMore = page.count >= Self.pageSize
            state = .loaded
        } catch is CancellationError {
            return
        } catch {
            state = .failed(ErrorText.describe(error))
        }
    }

    func loadMore() async {
        guard canLoadMore, !isLoadingMore, let before = items.map(\.cursor).min() else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await fetch(before: before)
            let known = Set(items.map(\.cursor))
            let fresh = page.filter { !known.contains($0.cursor) }
            items += fresh
            // Fewer than a page, or a page with nothing new: the end.
            canLoadMore = page.count >= Self.pageSize && !fresh.isEmpty
        } catch {
            canLoadMore = false
        }
    }

    private func fetch(before: Double?) async throws -> [ActivityItem] {
        let near = origin.map { (latitude: $0.latitude, longitude: $0.longitude) }
        return try await api.activity(limit: Self.pageSize, near: near, km: near == nil ? nil : km, before: before)
    }
}
