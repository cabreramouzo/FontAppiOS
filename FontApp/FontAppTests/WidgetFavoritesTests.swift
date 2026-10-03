import Foundation
import Testing
@testable import FontApp

struct WidgetFavoritesTests {
    @Test func selectionNeverTransfersAcrossAccountsOrServers() {
        let font = WidgetFavorite(id: UUID(), name: nil, lastWaterStatus: "dry", lastUpdate: .now, conflict: true)
        let production = URL(string: "https://fontapp.fly.dev")!
        let first = WidgetFavoritesSnapshot(scope: "production|alice", baseURL: production, fountains: [font])
        let identifier = WidgetFavoritesStore.identifier(font, in: first)
        #expect(WidgetFavoritesStore.selected(identifier, in: first)?.conflict == true)
        #expect(WidgetFavoritesStore.selected(identifier, in: nil) == nil)
        #expect(WidgetFavoritesStore.selected(identifier, in: .init(scope: "production|bob", baseURL: production, fountains: [font])) == nil)
        #expect(WidgetFavoritesStore.selected(identifier, in: .init(scope: "development|alice", baseURL: production, fountains: [font])) == nil)
        #expect(WidgetFavoritesStore.selected(identifier, in: .init(scope: first.scope, baseURL: production, fountains: [])) == nil)
    }

    @Test func signOutAndAccountSwitchEraseSharedReportCaches() {
        let name = "widget-test-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let snapshot = WidgetFavoritesSnapshot(scope: "alice", baseURL: URL(string: "https://fontapp.fly.dev")!, fountains: [])
        WidgetFavoritesStore.write(snapshot, to: defaults)
        defaults.set(Data([1]), forKey: "widget.detail.alice")
        WidgetFavoritesStore.write(snapshot, to: defaults)
        #expect(defaults.data(forKey: "widget.detail.alice") != nil)
        WidgetFavoritesStore.write(.init(scope: "bob", baseURL: snapshot.baseURL, fountains: []), to: defaults)
        #expect(defaults.data(forKey: "widget.detail.alice") == nil)
        defaults.set(Data([2]), forKey: "widget.detail.bob")
        WidgetFavoritesStore.write(nil, to: defaults)
        #expect(WidgetFavoritesStore.read(from: defaults) == nil)
        #expect(defaults.data(forKey: "widget.detail.bob") == nil)
    }
}
