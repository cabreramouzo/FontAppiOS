import CoreLocation
import SwiftUI

/// The "Me" tab: what is yours — who you are, your score and collection, the fountains
/// that depend on you, your fountains and reviews — with the bell and signing out.
/// Deleting the account lives in Settings, as on the web. Favourites have their own tab.
struct MeScreen: View {
    @Environment(SessionStore.self) private var session
    @Environment(Outbox.self) private var outbox
    @Environment(LocationService.self) private var location
    @State private var showsSignIn = false
    @State private var isSigningOut = false
    @State private var profile = ProfileModel()

    var body: some View {
        NavigationStack {
            Group {
                if session.isSignedIn {
                    account
                } else if !outbox.items.isEmpty {
                    // Signed out with contributions still on the phone: show them, they
                    // are why signing in matters right now.
                    List {
                        Section {
                            Button(L10n.t("nav.enter")) { showsSignIn = true }.frame(minHeight: 44)
                        } footer: {
                            Text(L10n.t("ios.signInPrompt"))
                        }
                        PendingSection()
                        Section {
                            NavigationLink(L10n.t("nav.guide")) { GuideScreen() }
                            LegalLink()
                        }
                    }
                } else {
                    ContentUnavailableView {
                        Label(L10n.t("nav.profile"), systemImage: "person.crop.circle")
                    } description: {
                        Text(L10n.t("ios.signInPrompt"))
                    } actions: {
                        Button(L10n.t("nav.enter")) { showsSignIn = true }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        // Before an account: what it is for, and the rules of the game.
                        NavigationLink(L10n.t("nav.guide")) { GuideScreen() }
                        LegalLink()
                    }
                }
            }
            .navigationTitle(L10n.t("nav.profile"))
            .navigationDestination(for: UUID.self) { FontDetailView(fontID: $0) }
            .toolbar {
                if session.isSignedIn { ToolbarItem(placement: .topBarTrailing) { BellButton() } }
            }
            .sheet(isPresented: $showsSignIn) { SignInView() }
        }
    }

    private var account: some View {
        List {
            Section {
                if let user = session.user {
                    ProfileHeader(user: user, staff: session.isStaff)
                    NavigationLink {
                        SettingsScreen()
                    } label: {
                        Label(L10n.t("settings.title"), systemImage: "gearshape")
                            .frame(minHeight: 44)
                    }
                } else {
                    ProgressView()
                }
            }
            PendingSection()
            if let game = profile.game { GameSection(game: game) }
            if let collection = profile.collection { CollectionSection(collection: collection) }
            if let guarded = profile.guarded { GuardedSection(fonts: guarded) }
            if let failed = profile.failed {
                Section { Text(failed).foregroundStyle(.secondary) }
            }
            CappedSection(title: L10n.t("profile.myFonts"), systemImage: "mappin.and.ellipse",
                          hint: L10n.t("profile.myFontsHint"), empty: L10n.t("profile.noFonts"),
                          items: profile.fonts) { ProfileFontRow(font: $0) }
            CappedSection(title: L10n.t("profile.myReviews"), systemImage: "bubble.left",
                          empty: L10n.t("profile.noReviews"),
                          items: profile.comments) { ProfileReviewRow(comment: $0) }
            Section {
                Button(role: .destructive) {
                    isSigningOut = true
                    Task {
                        await session.signOut()
                        isSigningOut = false
                    }
                } label: {
                    HStack {
                        Text(L10n.t("nav.logout"))
                        if isSigningOut { Spacer(); ProgressView() }
                    }
                    .frame(minHeight: 44)
                }
                .disabled(isSigningOut)
            }
            Section {
                NavigationLink { GuideScreen() } label: {
                    Label(L10n.t("nav.guide"), systemImage: "questionmark.circle").frame(minHeight: 44)
                }
                NavigationLink { GamificationGuideScreen() } label: {
                    Label(L10n.t("gamePage.title"), systemImage: "drop").frame(minHeight: 44)
                }
                LegalLink()
            }
        }
        .refreshable { await reload() }
        // Switching the game off or on in Settings changes what the profile shows.
        .task(id: ProfileKey(user: session.userID, gameOff: session.user?.gamificationOptOut)) {
            if profile.owner != session.userID { profile.clear(for: session.userID) }
            await reload()
        }
    }

    private func reload() async {
        async let account: Void = session.refresh()
        // Only a position the app already has: the profile never asks for permission.
        let near = location.location.map { (latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) }
        async let lists: Void = profile.load(near: near)
        _ = await (account, lists)
    }
}

private struct ProfileKey: Equatable {
    let user: UUID?
    let gameOff: Bool?
}

extension Color {
    /// Staff accounts contribute in this purple, so it is never done as staff by mistake.
    static let staff = Color(hex: 0x7C3AED)
}
