import Foundation
import WidgetKit

/// Public fountain data only. The widget never receives an authentication token.
nonisolated struct WidgetFavorite: Codable, Identifiable, Sendable {
    let id: UUID
    var name: String?
    var lastWaterStatus: String?
    var lastUpdate: Date?
    var conflict: Bool
    var unavailable: Bool = false
}

nonisolated struct WidgetFavoritesSnapshot: Codable, Sendable {
    let scope: String
    let baseURL: URL
    var fountains: [WidgetFavorite]
}

nonisolated enum WidgetFavoritesStore {
    static let group = "group.net.fontapp.FontApp"
    static let kind = "favorite"
    static let key = "widget.favorites.v1"

    static func read(from defaults: UserDefaults? = UserDefaults(suiteName: group)) -> WidgetFavoritesSnapshot? {
        defaults?.data(forKey: key).flatMap { try? JSONDecoder().decode(WidgetFavoritesSnapshot.self, from: $0) }
    }

    static func write(_ snapshot: WidgetFavoritesSnapshot?, to defaults: UserDefaults? = UserDefaults(suiteName: group)) {
        if read(from: defaults)?.scope != snapshot?.scope {
            let keys = defaults.map { Array($0.dictionaryRepresentation().keys) } ?? []
            for key in keys where key.hasPrefix("widget.detail.") {
                defaults?.removeObject(forKey: key)
            }
        }
        if let snapshot, let data = try? JSONEncoder().encode(snapshot) {
            defaults?.set(data, forKey: key)
        } else {
            defaults?.removeObject(forKey: key)
        }
        WidgetCenter.shared.reloadTimelines(ofKind: kind)
    }

    static func identifier(_ font: WidgetFavorite, in snapshot: WidgetFavoritesSnapshot) -> String {
        "\(snapshot.scope)|\(font.id.uuidString)"
    }

    static func selected(_ identifier: String, in snapshot: WidgetFavoritesSnapshot?) -> WidgetFavorite? {
        guard let snapshot else { return nil }
        return snapshot.fountains.first { self.identifier($0, in: snapshot) == identifier }
    }
}
