import Foundation
import Observation

/// Your starred fountains: the Favourites tab and the star on a fountain's page read the
/// same list, so starring in one shows in the other at once.
///
/// The last list is kept on the phone, per account: favourites are what you look at on the
/// way, often without signal, and "you have none yet" would be a lie there.
@Observable
final class Favorites {
    enum State: Equatable { case idle, loading, loaded, failed(String) }

    private(set) var items: [FontSummary] = []
    private(set) var state: State = .idle

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var account: UUID?

    init(api: APIClient = .shared, defaults: UserDefaults = .standard) {
        self.api = api
        self.defaults = defaults
    }

    func contains(_ id: UUID) -> Bool { items.contains { $0.id == id } }

    /// A new session (or none): show that account's saved list straight away.
    func sessionChanged(to userID: UUID?) {
        account = userID
        items = userID.flatMap(saved) ?? []
        state = .idle
    }

    func reload() async {
        guard let requested = account else { return }
        if items.isEmpty { state = .loading }
        do {
            let fresh = try await api.myFavorites()
            guard requested == account else { return }
            items = fresh
            state = .loaded
            save()
        } catch is CancellationError {
            return
        } catch {
            guard requested == account else { return }
            state = .failed(ErrorText.describe(error))
        }
    }

    /// Stars or unstars at once, and puts it back if the server says no. `font` is what
    /// the list will show until the next reload.
    func toggle(_ font: FontSummary) async throws {
        let on = !contains(font.id)
        let before = items
        items = on ? [font] + items : items.filter { $0.id != font.id }
        do {
            try await api.setFavorite(font.id, on)
            save()
        } catch {
            items = before
            throw error
        }
    }

    private var key: String? { account.map { "favorites.\($0.uuidString)" } }

    private func saved(_ userID: UUID) -> [FontSummary]? {
        defaults.data(forKey: "favorites.\(userID.uuidString)")
            .flatMap { try? JSONDecoder().decode([FontSummary].self, from: $0) }
    }

    private func save() {
        guard let key else { return }
        defaults.set(try? JSONEncoder().encode(items), forKey: key)
    }
}

extension FontDetail {
    /// What a list row needs, for a fountain starred from its page.
    nonisolated var summary: FontSummary {
        FontSummary(id: id, name: name, latitude: latitude, longitude: longitude, image: image,
                    description: description, source: source, drinkable: drinkable, country: country,
                    region: region, createdAt: createdAt, lastWaterStatus: lastWaterStatus,
                    lastUpdate: lastUpdate, latestConfirmations: nil, recentStatusReporters: nil,
                    recentStatusConflict: statusConflict, municipality: municipality)
    }
}
