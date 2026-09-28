import CoreLocation
import SwiftUI

/// The Favourites tab: the fountains you starred, where they are and how far. It takes the Zones tab's place while Zones waits.
struct FavoritesScreen: View {
    @Environment(Favorites.self) private var favorites
    @Environment(SessionStore.self) private var session
    @Environment(LocationService.self) private var location
    @State private var showsSignIn = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(L10n.t("profile.myFavorites"))
                .navigationDestination(for: UUID.self) { FontDetailView(fontID: $0) }
                .toolbar {
                    if session.isSignedIn { ToolbarItem(placement: .topBarTrailing) { BellButton() } }
                }
                .sheet(isPresented: $showsSignIn) { SignInView() }
        }
    }

    @ViewBuilder private var content: some View {
        if !session.isSignedIn {
            ContentUnavailableView {
                Label(L10n.t("profile.myFavorites"), systemImage: "star")
            } description: {
                Text(L10n.t("ios.favorites.signedOut"))
            } actions: {
                Button(L10n.t("nav.enter")) { showsSignIn = true }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        } else if favorites.items.isEmpty {
            switch favorites.state {
            case .idle, .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ContentUnavailableView {
                    Label(L10n.t("profile.myFavorites"), systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button(L10n.t("activity.retry")) { Task { await favorites.reload() } }
                }
            case .loaded:
                ContentUnavailableView {
                    Label(L10n.t("profile.noFavorites"), systemImage: "star")
                } description: {
                    Text(L10n.t("ios.favorites.howTo"))
                }
            }
        } else {
            List {
                if case .failed(let message) = favorites.state {
                    // Without signal the saved list stays; say it may be behind.
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    ForEach(favorites.items) { FavoriteRow(font: $0, from: location.location) }
                } footer: {
                    Text(L10n.t("profile.myFavoritesHint"))
                }
            }
            .refreshable { await favorites.reload() }
        }
    }
}

private struct FavoriteRow: View {
    let font: FontSummary
    let from: CLLocation?

    var body: some View {
        NavigationLink(value: font.id) {
            HStack(spacing: 12) {
                Text(font.source?.emoji ?? "💧").font(.title3).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.fontName(font.name))
                    // No water status: `/auth/me/favorites` sends the bare fountain, and
                    // reading its absence as "never checked" would be false.
                    Text([font.municipality ?? font.region, distance].compactMap { $0 }.joined(separator: " · "))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 44)
        }
    }

    private var distance: String? {
        guard let from else { return nil }
        let meters = from.distance(from: CLLocation(latitude: font.latitude, longitude: font.longitude))
        return Measurement(value: meters, unit: UnitLength.meters).formatted(.measurement(width: .abbreviated, usage: .road))
    }
}
