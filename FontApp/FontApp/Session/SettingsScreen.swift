import SwiftUI

/// Settings, as the web's `/me/settings`: the account's name, username and email, what
/// others see, the emails you get and whether your level is shared. Switches save at
/// once and go back if the server says no; the account fields save with a button.
///
/// Push settings are not here: native push (APNs) does not exist yet.
struct SettingsScreen: View {
    @Environment(SessionStore.self) private var session
    @State private var name = ""
    @State private var username = ""
    @State private var email = ""
    @State private var isSaving = false
    @State private var error: String?
    @State private var saved = false

    var body: some View {
        Form {
            if let error {
                Section { Text(error).foregroundStyle(.red) }
            }
            if let user = session.user {
                account(user)
                switches(user)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(L10n.t("settings.title"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: fill)
        .sensoryFeedback(.success, trigger: saved)
    }

    private func account(_ user: UserResponse) -> some View {
        Section {
            TextField(L10n.t("profile.name"), text: $name)
                .textContentType(.name)
            TextField(L10n.t("profile.username"), text: $username)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField(L10n.t("profile.email"), text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button {
                saveAccount()
            } label: {
                HStack {
                    Text(L10n.t("form.save")).bold()
                    if isSaving { Spacer(); ProgressView() }
                }
                .frame(minHeight: 44)
            }
            .disabled(!accountChanged(user) || isSaving)
        } header: {
            Text(L10n.t("settings.account"))
        } footer: {
            // Changing it breaks the old profile link and past mentions: said before, not after.
            if username.trimmingCharacters(in: .whitespaces) != user.username {
                Text(L10n.t("profile.usernameWarning"))
            } else {
                Text(L10n.t("profile.usernameRules"))
            }
        }
    }

    @ViewBuilder private func switches(_ user: UserResponse) -> some View {
        Section {
            setting(L10n.t("privacy.namePublic"), hint: L10n.t("privacy.namePublicHint"),
                    value: user.namePublic ?? true) { $0.namePublic = $1 }
            setting(L10n.t("privacy.emailPublic"), hint: L10n.t("privacy.emailPublicHint"),
                    value: user.emailPublic ?? false) { $0.emailPublic = $1 }
        } header: {
            Text(L10n.t("privacy.title"))
        } footer: {
            Text(L10n.t("privacy.intro"))
        }
        Section(L10n.t("notif.title")) {
            setting(L10n.t("notif.weekly"), hint: L10n.t("notif.weeklyHint"),
                    value: user.weeklyDigest ?? true) { $0.weeklyDigest = $1 }
            setting(L10n.t("notif.mentions"), hint: L10n.t("notif.mentionsHint"),
                    value: user.mentionEmails ?? true) { $0.mentionEmails = $1 }
        }
        pushSection(user)
        Section {
            let shared = !(user.gamificationOptOut ?? false)
            setting(L10n.t("game.share"), hint: nil, value: shared) { $0.gamificationOptOut = !$1 }
        } header: {
            Text(L10n.t("game.title"))
        } footer: {
            let shared = !(user.gamificationOptOut ?? false)
            // What switching it off costs, told before and not after.
            Text(shared ? [L10n.t("game.shareKeeps"), L10n.t("game.shareOffHides"), L10n.t("game.shareOffCaps")].joined(separator: " ")
                        : L10n.t("game.shareKeeps"))
        }
    }

    /// Notices on this iPhone: the system's permission first, then which groups, as the
    /// web groups them (a fountain you follow, someone talking to you, administration)
    /// instead of one switch per event nobody reads. The groups only once it is on:
    /// asking which before saying yes is two decisions for nothing.
    @ViewBuilder private func pushSection(_ user: UserResponse) -> some View {
        let push = PushNotifications.shared
        Section {
            switch push.status {
            case .authorized, .provisional, .ephemeral:
                Label(L10n.t("ios.push.on"), systemImage: "bell.badge").frame(minHeight: 44)
                setting(L10n.t("notif.pushFonts"), hint: nil, value: user.pushFontUpdates ?? true) { $0.pushFontUpdates = $1 }
                setting(L10n.t("notif.pushMentions"), hint: nil, value: user.pushMentions ?? true) { $0.pushMentions = $1 }
                // Only to whoever really gets them.
                if user.isAdmin == true || user.canManageFonts {
                    setting(L10n.t("notif.pushAdmin"), hint: nil, value: user.pushAdmin ?? true) { $0.pushAdmin = $1 }
                }
                Button(L10n.t("notif.pushTest")) {
                    Task {
                        do { try await APIClient.shared.sendTestPush() } catch { self.error = ErrorText.describe(error) }
                    }
                }
                .frame(minHeight: 44)
            case .denied:
                Text(L10n.t("ios.push.denied")).font(.subheadline).foregroundStyle(.secondary)
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    Link(L10n.t("ios.push.openSettings"), destination: url).frame(minHeight: 44)
                }
            default:
                Button(L10n.t("ios.push.enable")) { Task { await push.enable() } }.frame(minHeight: 44)
            }
        } header: {
            Text(L10n.t("notif.push"))
        } footer: {
            Text(L10n.t("ios.push.hint"))
        }
        .task { await push.refresh() }
    }

    /// A switch that saves on change. The account's value is the truth: while saving, and
    /// after a refusal, it shows what the server has.
    private func setting(_ title: String, hint: String?, value: Bool,
                         apply: @escaping (inout ProfileUpdate, Bool) -> Void) -> some View {
        Toggle(isOn: Binding(get: { value }, set: { on in save { apply(&$0, on) } })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let hint { Text(hint).font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .disabled(isSaving)
        .frame(minHeight: 44)
    }

    private func fill() {
        guard let user = session.user else { return }
        name = user.name
        username = user.username
        email = user.email ?? ""
    }

    private func accountChanged(_ user: UserResponse) -> Bool {
        name.trimmingCharacters(in: .whitespaces) != user.name
            || username.trimmingCharacters(in: .whitespaces) != user.username
            || email.trimmingCharacters(in: .whitespaces) != (user.email ?? "")
    }

    private func saveAccount() {
        let name = name.trimmingCharacters(in: .whitespaces)
        let username = username.trimmingCharacters(in: .whitespaces)
        let email = email.trimmingCharacters(in: .whitespaces)
        if let problem = SignUpRules.accountProblem(name: name, username: username, email: email) {
            error = problem.message
            return
        }
        save {
            $0.name = name
            $0.username = username
            $0.email = email
        }
    }

    private func save(_ change: @escaping (inout ProfileUpdate) -> Void) {
        isSaving = true
        error = nil
        Task {
            defer { isSaving = false }
            do {
                try await session.update(change)
                fill()
                saved.toggle()
            } catch {
                self.error = ErrorText.describe(error)
            }
        }
    }
}
