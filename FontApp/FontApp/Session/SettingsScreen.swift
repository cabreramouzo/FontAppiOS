import SwiftUI

/// The settings index, as the web's `/me/settings`: one screen per topic, like the
/// phone's own Settings.
///
/// Every row shows its state ("@xavi", "Name visible", "Weekly digest · Notices on this
/// iPhone"): an index of bare links would be worse than one long page, one more tap that
/// says nothing. You only go in to change something.
///
/// The danger zone stays here, folded: deleting the account is an action, not a topic,
/// and it must be findable without exploring, but never one tap away.
struct SettingsScreen: View {
    @Environment(SessionStore.self) private var session
    @Environment(Outbox.self) private var outbox
    @State private var showsDangerZone = false
    @State private var confirmsDeletion = false
    @State private var isDeleting = false
    @State private var isSigningOut = false
    @State private var deletionError: String?

    var body: some View {
        List {
            if let user = session.user {
                Section {
                    row(L10n.t("settings.account"), systemImage: "person", state: "@\(user.username)") {
                        AccountSettingsScreen()
                    }
                    row(L10n.t("privacy.title"), systemImage: "lock", state: privacy(user)) {
                        PrivacySettingsScreen()
                    }
                    row(L10n.t("notif.title"), systemImage: "bell", state: notices(user)) {
                        NotificationsSettingsScreen()
                    }
                    row(L10n.t("game.title"), systemImage: "drop",
                        state: (user.gamificationOptOut ?? false) ? L10n.t("game.rowHidden") : L10n.t("game.rowShared")) {
                        ContributionSettingsScreen()
                    }
                } footer: {
                    Text(L10n.t("settings.intro"))
                }
                // Signing out goes last but one, as in the phone's own Settings.
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
                dangerZone
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(L10n.t("settings.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await PushNotifications.shared.refresh() }
    }

    private func row<Destination: View>(_ title: String, systemImage: String, state: String,
                                        @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink(destination: destination) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    if !state.isEmpty {
                        Text(state).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            } icon: {
                Image(systemName: systemImage).foregroundStyle(.secondary)
            }
            // The thumb's size, as the web's 56 px rows.
            .frame(minHeight: 48)
        }
    }

    /// What others see, not how many switches are on: the question brought here is
    /// "what do people see of me?".
    private func privacy(_ user: UserResponse) -> String {
        let visible = [(user.namePublic ?? true) ? L10n.t("privacy.rowName") : nil,
                       (user.emailPublic ?? false) ? L10n.t("privacy.rowEmail") : nil].compactMap { $0 }
        return visible.isEmpty ? L10n.t("privacy.rowOnlyUser") : visible.joined(separator: " · ")
    }

    private func notices(_ user: UserResponse) -> String {
        let push = PushNotifications.shared.status
        let on = [(user.weeklyDigest ?? true) ? L10n.t("notif.rowWeekly") : nil,
                  (push == .authorized || push == .provisional || push == .ephemeral) ? L10n.t("notif.rowPush") : nil]
            .compactMap { $0 }
        return on.isEmpty ? L10n.t("notif.rowNone") : on.joined(separator: " · ")
    }

    // MARK: Danger zone

    /// Apple requires deleting the account from inside the app (App Store rule 5.1.1(v)).
    /// The server anonymises it: personal data goes, contributions stay without a name.
    private var dangerZone: some View {
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
                .disabled(isDeleting)
                .confirmsDestructive(L10n.t("profile.deleteAccount"), isPresented: $confirmsDeletion,
                                     action: L10n.t("profile.deleteAccount"), message: deletionMessage,
                                     perform: deleteAccount)
                if let deletionError {
                    Text(deletionError).foregroundStyle(.red)
                }
            } label: {
                Label(L10n.t("profile.dangerZone"), systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .frame(minHeight: 44)
            }
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
