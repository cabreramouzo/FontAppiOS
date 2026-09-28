import SwiftUI

struct ContentView: View {
    @Environment(Outbox.self) private var outbox
    @State private var tab = AppTab.map

    enum AppTab: Hashable { case map, news, favorites, me }

    var body: some View {
        TabView(selection: $tab) {
            Tab(L10n.t("nav.map"), systemImage: "map", value: AppTab.map) {
                MapScreen()
            }
            Tab(L10n.t("news.title"), systemImage: "newspaper", value: AppTab.news) {
                NewsScreen()
            }
            // Zones is on hold (28/09/2026): favourites are what people come back to on the way.
            Tab(L10n.t("ios.tab.favorites"), systemImage: "star", value: AppTab.favorites) {
                FavoritesScreen()
            }
            // The count of contributions still on the phone, where they can be seen and sent.
            Tab(L10n.t("nav.profile"), systemImage: "person.crop.circle", value: AppTab.me) {
                MeScreen()
            }
            .badge(outbox.items.count)
        }
        // A GPX opened from another app is a route to show on the map.
        .onOpenURL { url in if url.isFileURL { tab = .map } }
    }
}

/// A tab that exists so the app's shape is visible, but whose screen is not built yet.
struct ComingSoonView: View {
    let title: String
    let systemImage: String

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label(L10n.t("ios.comingSoon"), systemImage: systemImage)
            } description: {
                Text(L10n.t("ios.comingSoonBody"))
            }
            .navigationTitle(title)
        }
    }
}

#Preview {
    ContentView()
        .environment(LocationService())
        .environment(SessionStore())
        .environment(Outbox.shared)
        .environment(OfflineZones.shared)
        .environment(Favorites())
        .environment(Bell())
}
