import CoreLocation
import Foundation
import Observation
import SwiftUI

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
    /// Pinned ones go first, in the order they were pinned. The server knows no order nor
    /// pins: both are yours, kept on this phone per account.
    private(set) var pinned: [UUID] = []
    /// Your own order; ids not in it (starred later, or on the web) go first, newest first.
    private(set) var order: [UUID] = []

    enum Sort: String, CaseIterable { case mine, nearest, name }

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var account: UUID?

    init(api: APIClient = .shared, defaults: UserDefaults = .standard) {
        self.api = api
        self.defaults = defaults
    }

    func contains(_ id: UUID) -> Bool { items.contains { $0.id == id } }
    func isPinned(_ id: UUID) -> Bool { pinned.contains(id) }

    /// The list as shown: pinned first, then the rest by the chosen order.
    func arranged(_ sort: Sort, from location: CLLocation?) -> (pinned: [FontSummary], rest: [FontSummary]) {
        let pins = pinned.compactMap { id in items.first { $0.id == id } }
        let others = items.filter { !pinned.contains($0.id) }
        switch sort {
        case .mine:
            let rank = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
            let unplaced = others.filter { rank[$0.id] == nil }
            let placed = others.filter { rank[$0.id] != nil }.sorted { rank[$0.id]! < rank[$1.id]! }
            return (pins, unplaced + placed)
        case .nearest:
            guard let location else { return (pins, others) }
            return (pins, others.sorted {
                location.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))
                    < location.distance(from: CLLocation(latitude: $1.latitude, longitude: $1.longitude))
            })
        case .name:
            return (pins, others.sorted {
                L10n.fontName($0.name).localizedStandardCompare(L10n.fontName($1.name)) == .orderedAscending
            })
        }
    }

    func togglePin(_ id: UUID) {
        if let at = pinned.firstIndex(of: id) { pinned.remove(at: at) } else { pinned.append(id) }
        saveArrangement()
    }

    /// Moves within the pinned group or within the rest, as the list shows them.
    func move(pinnedGroup: Bool, visible: [FontSummary], from source: IndexSet, to destination: Int) {
        var ids = visible.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        if pinnedGroup { pinned = ids } else { order = ids }
        saveArrangement()
    }

    /// Unstars several at once, each on the server; any it refuses comes back.
    func remove(_ fonts: [FontSummary]) async throws {
        var firstError: (any Error)?
        for font in fonts where contains(font.id) {
            do { try await toggle(font) } catch { firstError = firstError ?? error }
        }
        if let firstError { throw firstError }
    }

    /// A new session (or none): show that account's saved list straight away.
    func sessionChanged(to userID: UUID?) {
        account = userID
        items = userID.flatMap(saved) ?? []
        let arrangement = userID.flatMap { defaults.data(forKey: "favorites.arrangement.\($0.uuidString)") }
            .flatMap { try? JSONDecoder().decode(Arrangement.self, from: $0) }
        pinned = arrangement?.pinned ?? []
        order = arrangement?.order ?? []
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
            if !on {
                pinned.removeAll { $0 == font.id }
                order.removeAll { $0 == font.id }
                saveArrangement()
            }
        } catch {
            items = before
            throw error
        }
    }

    private var key: String? { account.map { "favorites.\($0.uuidString)" } }

    private struct Arrangement: Codable { var pinned: [UUID]; var order: [UUID] }

    private func saveArrangement() {
        guard let account else { return }
        defaults.set(try? JSONEncoder().encode(Arrangement(pinned: pinned, order: order)),
                     forKey: "favorites.arrangement.\(account.uuidString)")
    }

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
