import SwiftUI

/// The "Me" tab: the account, the bell, signing out and deleting the account. The rest of
/// the web's profile comes later.
struct MeScreen: View {
    @Environment(SessionStore.self) private var session
    @Environment(Outbox.self) private var outbox
    @State private var showsSignIn = false
    @State private var isSigningOut = false
    @State private var confirmsDeletion = false
    @State private var isDeleting = false
    @State private var deletionError: String?

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
                    }
                }
            }
            .navigationTitle(L10n.t("nav.profile"))
            .toolbar {
                if session.isSignedIn { ToolbarItem(placement: .topBarTrailing) { BellButton() } }
            }
            .sheet(isPresented: $showsSignIn) { SignInView() }
        }
    }

    private var account: some View {
        List {
            Section(L10n.t("settings.account")) {
                if let user = session.user {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(user.name).font(.headline)
                            if session.isStaff {
                                Text(L10n.t("staff.tag"))
                                    .font(.caption.bold())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .foregroundStyle(.white)
                                    .background(Color.staff, in: Capsule())
                            }
                        }
                        Text("@\(user.username)").foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } else {
                    ProgressView()
                }
            }
            PendingSection()
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
            deletion
        }
        .task { await session.refresh() }
    }

    /// Apple requires deleting the account from inside the app (App Store rule 5.1.1(v)).
    /// The server anonymises it: personal data goes, contributions stay without a name.
    private var deletion: some View {
        Section {
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
        } header: {
            Text(L10n.t("profile.dangerZone"))
        } footer: {
            Text(L10n.t("profile.dangerZoneHint"))
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

extension Color {
    /// Staff accounts contribute in this purple, so it is never done as staff by mistake.
    static let staff = Color(hex: 0x7C3AED)
}
