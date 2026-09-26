import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            Tab(L10n.t("nav.map"), systemImage: "map") {
                MapScreen()
            }
            Tab(L10n.t("news.title"), systemImage: "newspaper") {
                NewsScreen()
            }
            Tab(L10n.t("zones.title"), systemImage: "globe.europe.africa") {
                ComingSoonView(title: L10n.t("zones.title"), systemImage: "globe.europe.africa")
            }
            Tab(L10n.t("nav.profile"), systemImage: "person.crop.circle") {
                ComingSoonView(title: L10n.t("nav.profile"), systemImage: "person.crop.circle")
            }
        }
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
}
