import CoreLocation
import SwiftUI

/// The "Me" tab: what is yours — who you are, your score and collection, the fountains
/// that depend on you, your fountains and reviews — with the bell, signing out and
/// deleting the account. Favourites have their own tab.
struct MeScreen: View {
    @Environment(SessionStore.self) private var session
    @Environment(Outbox.self) private var outbox
    @Environment(LocationService.self) private var location
    @State private var showsSignIn = false
    @State private var isSigningOut = false
    @State private var confirmsDeletion = false
    @State private var showsDangerZone = false
    @State private var isDeleting = false
    @State private var deletionError: String?
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
                .disabled(isSigningOut || isDeleting)
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
            deletion
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

    /// Apple requires deleting the account from inside the app (App Store rule 5.1.1(v)).
    /// The server anonymises it: personal data goes, contributions stay without a name.
    /// Folded by default: deleting cannot be undone, so it takes a deliberate tap to
    /// even see the button, and one more to confirm.
    private var deletion: some View {
        Section {
            DisclosureGroup(isExpanded: $showsDangerZone) {
                Text(L10n.t("profile.dangerZoneHint"))
                    .font(.footnote).foregroundStyle(.secondary)
                Button(role: .destructive) { confirmsDeletion = true } label: {
                    HStack {
                        Label(L10n.t("profile.deleteAccount"), systemImage: "trash")
                            .foregroundStyle(.red)
                        if isDeleting { Spacer(); ProgressView() }
                    }
                    .frame(minHeight: 44)
                }
                .disabled(isDeleting || isSigningOut)
                if let deletionError {
                    Text(deletionError).foregroundStyle(.red)
                }
            } label: {
                Label(L10n.t("profile.dangerZone"), systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 44)
            }
        }
        .confirmationDialog(L10n.t("profile.deleteAccount"), isPresented: $confirmsDeletion, titleVisibility: .visible) {
            Button(L10n.t("profile.deleteAccount"), role: .destructive, action: deleteAccount)
            Button(role: .cancel) {}
        } message: {
            Text(deletionMessage)
        }
    }

    /// Contributions still on the phone would be lost for good: say so, with how many.
    private var deletionMessage: String {
        let pending = outbox.items.filter { $0.userID != nil && $0.userID == session.userID }.count
        let warning = L10n.t("profile.confirmDelete")
        guard pending > 0 else { return warning }
        return warning + "\n\n" + L10n.t("ios.deleteAccount.pending", ["n": pending])
    }

    private func deleteAccount() {
        guard let userID = session.userID else { return }
        isDeleting = true
        deletionError = nil
        Task {
            defer { isDeleting = false }
            // What is waiting goes out first, under the account, like any contribution:
            // the server keeps contributions anonymously after the deletion.
            _ = await outbox.flush()
            do {
                try await session.deleteAccount()
                outbox.discard(queuedBy: userID)
            } catch {
                deletionError = ErrorText.describe(error)
            }
        }
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
