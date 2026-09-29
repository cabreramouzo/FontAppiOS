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
    @State private var passkeys: [PasskeySummary] = []
    @State private var naming = false
    @State private var passkeyLabel = ""
    @State private var addingPasskey = false
    @State private var removing: PasskeySummary?

    var body: some View {
        Form {
            if let error {
                Section { Text(error).foregroundStyle(.red) }
            }
            if let user = session.user {
                account(user)
                if Passkeys.available(for: APIClient.shared.baseURL) { passkeySection }
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

    /// Next to the account, as on the web: a way to sign in, like the password.
    private var passkeySection: some View {
        Section {
            ForEach(passkeys) { key in
                VStack(alignment: .leading, spacing: 2) {
                    Text(key.label)
                    if let date = key.lastUsedAt ?? key.createdAt {
                        Text(RelativeTime.string(since: date)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(minHeight: 44)
                .swipeActions {
                    Button(L10n.t("detail.delete"), role: .destructive) { removing = key }
                }
            }
            Button {
                passkeyLabel = L10n.t("passkey.defaultLabel")
                naming = true
            } label: {
                HStack {
                    Label(L10n.t("passkey.add"), systemImage: "person.badge.key")
                    if addingPasskey { Spacer(); ProgressView() }
                }
                .frame(minHeight: 44)
            }
            .disabled(addingPasskey)
        } header: {
            Text(L10n.t("passkey.title"))
        } footer: {
            Text(L10n.t("passkey.intro"))
        }
        .task { passkeys = (try? await APIClient.shared.passkeys()) ?? [] }
        .alert(L10n.t("passkey.namePrompt"), isPresented: $naming) {
            TextField(L10n.t("passkey.defaultLabel"), text: $passkeyLabel)
            Button(L10n.t("passkey.add"), action: addPasskey)
            Button(L10n.t("form.cancel"), role: .cancel) {}
        }
        .confirmationDialog(L10n.t("passkey.confirmDelete"),
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible, presenting: removing) { key in
            Button(L10n.t("detail.delete"), role: .destructive) { removePasskey(key) }
        }
    }

    private func addPasskey() {
        let label = passkeyLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        addingPasskey = true
        error = nil
        Task {
            defer { addingPasskey = false }
            do {
                let key = try await PasskeySheet.add(label: label.isEmpty ? L10n.t("passkey.defaultLabel") : label,
                                                     api: .shared)
                passkeys.insert(key, at: 0)
                saved.toggle()
            } catch where PasskeySheet.wasCancelled(error) {
            } catch {
                self.error = ErrorText.describe(error)
            }
        }
    }

    private func removePasskey(_ key: PasskeySummary) {
        Task {
            do {
                try await APIClient.shared.deletePasskey(key.id)
                passkeys.removeAll { $0.id == key.id }
            } catch {
                self.error = ErrorText.describe(error)
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
        passingBySection
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

    /// "Tell me when I pass by a fountain": local notices, only with "Always" location.
    /// The permission is asked when this is turned on, never before.
    @ViewBuilder private var passingBySection: some View {
        let passing = PassingBy.shared
        Section {
            Toggle(isOn: Binding(get: { passing.isEnabled }, set: { on in Task { await passing.setEnabled(on) } })) {
                Text(L10n.t("ios.passingBy.title"))
            }
            .frame(minHeight: 44)
            if passing.isBlocked {
                Text(L10n.t("ios.passingBy.needsAlways")).font(.subheadline).foregroundStyle(.secondary)
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    Link(L10n.t("ios.push.openSettings"), destination: url).frame(minHeight: 44)
                }
            }
        } footer: {
            Text(L10n.t("ios.passingBy.hint"))
        }
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
