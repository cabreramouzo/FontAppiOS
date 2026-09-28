import CoreLocation
import MapKit
import SwiftUI

/// The Favourites tab: the fountains you starred, where they are and how far. It takes the Zones tab's place while Zones waits.
struct FavoritesScreen: View {
    @Environment(Favorites.self) private var favorites
    @Environment(SessionStore.self) private var session
    @Environment(LocationService.self) private var location
    @Environment(\.showOnMap) private var showOnMap
    @State private var showsSignIn = false
    @State private var sort: Favorites.Sort = Self.savedSort
    @State private var query = ""
    @State private var editMode: EditMode = .inactive
    @State private var selection = Set<UUID>()
    @State private var error: String?

    private static var savedSort: Favorites.Sort {
        Favorites.Sort(rawValue: UserDefaults.standard.string(forKey: "favorites.sort") ?? "") ?? .mine
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(L10n.t("profile.myFavorites"))
                .navigationDestination(for: UUID.self) { FontDetailView(fontID: $0) }
                .toolbar {
                    if session.isSignedIn, !favorites.items.isEmpty {
                        ToolbarItem(placement: .topBarLeading) { EditButton() }
                    }
                    // Editing, the top right is for what to do with the selection; the
                    // bottom bar would sit under the tab bar.
                    if editMode.isEditing {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(role: .destructive) { removeSelected() } label: {
                                Text(L10n.t("ios.favorites.removeN", ["n": selection.count]))
                            }
                            .tint(.red)
                            .disabled(selection.isEmpty)
                        }
                    } else if session.isSignedIn {
                        if !favorites.items.isEmpty { ToolbarItem(placement: .topBarTrailing) { sortMenu } }
                        ToolbarItem(placement: .topBarTrailing) { BellButton() }
                    }
                }
                .environment(\.editMode, $editMode)
                .onChange(of: editMode.isEditing) { if !editMode.isEditing { selection = [] } }
                .onChange(of: sort) { UserDefaults.standard.set(sort.rawValue, forKey: "favorites.sort") }
                .alert(error ?? "", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                    Button("OK", role: .cancel) {}
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
            let arranged = favorites.arranged(sort, from: location.location)
            let pins = filtered(arranged.pinned), rest = filtered(arranged.rest)
            // Selecting only while editing: a selectable list swallows the tap that should
            // open the fountain.
            List(selection: editMode.isEditing ? $selection : nil) {
                if case .failed(let message) = favorites.state {
                    // Without signal the saved list stays; say it may be behind.
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
                if !pins.isEmpty {
                    Section {
                        rows(pins, pinnedGroup: true)
                    } header: {
                        Label(L10n.t("ios.favorites.pinned"), systemImage: "pin.fill")
                    }
                }
                Section {
                    rows(rest, pinnedGroup: false)
                } header: {
                    if !pins.isEmpty { Text(L10n.t("profile.myFavorites")) }
                } footer: {
                    // Dragging only means something in your own order.
                    Text(sort == .mine ? L10n.t("ios.favorites.manageHint") : L10n.t("profile.myFavoritesHint"))
                }
                if pins.isEmpty && rest.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic),
                        prompt: L10n.t("ios.favorites.filter"))
            .refreshable { await favorites.reload() }
        }
    }
}

extension FavoritesScreen {
    private var sortMenu: some View {
        Menu {
            Picker(L10n.t("ios.favorites.sort"), selection: $sort) {
                Label(L10n.t("ios.favorites.sortMine"), systemImage: "hand.draw").tag(Favorites.Sort.mine)
                Label(L10n.t("ios.favorites.sortNearest"), systemImage: "location").tag(Favorites.Sort.nearest)
                Label(L10n.t("ios.favorites.sortName"), systemImage: "textformat").tag(Favorites.Sort.name)
            }
        } label: {
            Label(L10n.t("ios.favorites.sort"), systemImage: "arrow.up.arrow.down")
        }
    }

    private func filtered(_ fonts: [FontSummary]) -> [FontSummary] {
        let term = query.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return fonts }
        return fonts.filter {
            [L10n.fontName($0.name), $0.municipality ?? "", $0.region ?? ""].contains {
                $0.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }
    }

    @ViewBuilder private func rows(_ fonts: [FontSummary], pinnedGroup: Bool) -> some View {
        ForEach(fonts) { font in
            FavoriteRow(font: font, from: location.location, pinned: favorites.isPinned(font.id))
                .tag(font.id)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { remove([font]) } label: {
                        Label(L10n.t("ios.favorites.remove"), systemImage: "star.slash")
                    }
                }
                .swipeActions(edge: .leading) {
                    pinButton(font).tint(.orange)
                }
                .contextMenu { menu(font) }
        }
        .onMove(perform: movable(pinnedGroup) ? { source, destination in
            favorites.move(pinnedGroup: pinnedGroup, visible: fonts, from: source, to: destination)
        } : nil)
    }

    /// Pins keep their own order always; the rest only in "my order", and not while filtered.
    private func movable(_ pinnedGroup: Bool) -> Bool {
        query.isEmpty && (pinnedGroup || sort == .mine)
    }

    private func pinButton(_ font: FontSummary) -> some View {
        let pinned = favorites.isPinned(font.id)
        return Button { withAnimation { favorites.togglePin(font.id) } } label: {
            Label(L10n.t(pinned ? "ios.favorites.unpin" : "ios.favorites.pin"), systemImage: pinned ? "pin.slash" : "pin")
        }
    }

    @ViewBuilder private func menu(_ font: FontSummary) -> some View {
        Button {
            let item = MKMapItem(location: CLLocation(latitude: font.latitude, longitude: font.longitude), address: nil)
            item.name = L10n.fontName(font.name)
            item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
        } label: {
            Label(L10n.t("detail.directions"), systemImage: "figure.walk")
        }
        if let showOnMap {
            Button { showOnMap(font) } label: { Label(L10n.t("detail.viewOnMap"), systemImage: "map") }
        }
        ShareLink(item: "\(L10n.t("detail.shareText", ["name": L10n.fontName(font.name)])) https://fontapp.net/fonts/\(font.id.uuidString.lowercased())") {
            Label(L10n.t("detail.share"), systemImage: "square.and.arrow.up")
        }
        pinButton(font)
        Divider()
        Button(role: .destructive) { remove([font]) } label: {
            Label(L10n.t("ios.favorites.remove"), systemImage: "star.slash")
        }
    }

    private func remove(_ fonts: [FontSummary]) {
        Task {
            do {
                try await favorites.remove(fonts)
            } catch {
                self.error = ErrorText.describe(error)
            }
        }
    }

    private func removeSelected() {
        let fonts = favorites.items.filter { selection.contains($0.id) }
        selection = []
        remove(fonts)
    }
}

private struct FavoriteRow: View {
    let font: FontSummary
    let from: CLLocation?
    var pinned = false

    var body: some View {
        NavigationLink(value: font.id) {
            HStack(spacing: 12) {
                Text(font.source?.emoji ?? "💧").font(.title3).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(L10n.fontName(font.name))
                        if pinned {
                            Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.orange)
                                .accessibilityLabel(L10n.t("ios.favorites.pinned"))
                        }
                    }
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
