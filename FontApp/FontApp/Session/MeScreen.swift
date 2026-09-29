import CoreLocation
import SwiftUI

/// The "Me" tab: what is yours — who you are, your score and collection, the fountains
/// that depend on you, your fountains and reviews — with the bell. Each list opens on its
/// own screen, so the profile fits about one screen. Signing out and deleting the
/// account live in Settings. Favourites have their own tab.
struct MeScreen: View {
    @Environment(SessionStore.self) private var session
    @Environment(Outbox.self) private var outbox
    @Environment(LocationService.self) private var location
    @State private var showsSignIn = false
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
            // Small: the name under the avatar is the real title of this page.
            .navigationBarTitleDisplayMode(session.isSignedIn ? .inline : .automatic)
            .navigationDestination(for: UUID.self) { FontDetailView(fontID: $0) }
            .toolbar {
                if session.isSignedIn {
                    // Settings as the gear, as in Apple's own apps: not a row of your data.
                    ToolbarItem(placement: .topBarLeading) {
                        NavigationLink { SettingsScreen() } label: { Image(systemName: "gearshape") }
                            .accessibilityLabel(L10n.t("settings.title"))
                    }
                    ToolbarItem(placement: .topBarTrailing) { BellButton() }
                }
            }
            .sheet(isPresented: $showsSignIn) { SignInView() }
        }
    }

    private var account: some View {
        List {
            if let user = session.user {
                Section {
                    ProfileHero(user: user, staff: session.isStaff, game: profile.game)
                    ImpactStrip(game: profile.game, visited: profile.collection?.visited)
                }
            } else {
                Section { ProgressView().frame(maxWidth: .infinity) }
            }
            // The one thing here that asks you to do something: said first, when true.
            if let guarded = profile.guarded, case let stale = guarded.filter(\.stale).count, stale > 0 {
                Section {
                    NavigationLink { guardedScreen(guarded) } label: {
                        Label(L10n.t("ios.profile.stale", ["n": stale]), systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                            .frame(minHeight: 44)
                    }
                }
            }
            PendingSection()
            if let failed = profile.failed {
                Section {
                    Text(failed).foregroundStyle(.secondary)
                    Button(L10n.t("error.retry")) { Task { await reload() } }.frame(minHeight: 44)
                }
            }
            Section {
                ProfileLinkRow(title: L10n.t("badges.title"), systemImage: "rosette") {
                    CollectionScreen(collection: profile.collection)
                }
                if let guarded = profile.guarded, !guarded.isEmpty {
                    ProfileLinkRow(title: L10n.t("guard.title"), systemImage: "shield", count: guarded.count) {
                        guardedScreen(guarded)
                    }
                }
                ProfileLinkRow(title: L10n.t("profile.myFonts"), systemImage: "mappin.and.ellipse",
                               count: profile.fonts?.count) {
                    ProfileListScreen(title: L10n.t("profile.myFonts"), hint: L10n.t("profile.myFontsHint"),
                                      empty: L10n.t("profile.noFonts"), items: profile.fonts ?? []) { ProfileFontRow(font: $0) }
                }
                ProfileLinkRow(title: L10n.t("profile.myReviews"), systemImage: "bubble.left",
                               count: profile.comments?.count) {
                    ProfileListScreen(title: L10n.t("profile.myReviews"), empty: L10n.t("profile.noReviews"),
                                      items: profile.comments ?? []) { ProfileReviewRow(comment: $0) }
                }
                if let user = session.user {
                    ProfileLinkRow(title: L10n.t("privacy.viewPublic"), systemImage: "person.crop.circle") {
                        UserProfileScreen(handle: user.username)
                    }
                }
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

    private func guardedScreen(_ fonts: [GuardedFont]) -> some View {
        List { GuardedSection(fonts: fonts) }
            .navigationTitle(L10n.t("guard.title"))
            .navigationBarTitleDisplayMode(.inline)
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
