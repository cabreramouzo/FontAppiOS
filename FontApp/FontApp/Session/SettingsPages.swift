import SwiftUI

/// The screens behind the settings index, one per topic, as the web's `/me/settings/*`.
/// Switches save at once through `SessionStore.update`, which sends the whole profile
/// with only the one change: a switch can never overwrite another with a default.

/// A switch that saves on change. The account's value is the truth: while saving, and
/// after a refusal, it shows what the server has.
struct SettingSwitch: View {
    let title: String
    var hint: String?
    let value: Bool
    let apply: (inout ProfileUpdate, Bool) -> Void
    @Binding var error: String?

    @Environment(SessionStore.self) private var session
    @State private var isSaving = false
    @State private var saved = false

    var body: some View {
        Toggle(isOn: Binding(get: { value }, set: save)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let hint { Text(hint).font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .disabled(isSaving)
        .frame(minHeight: 44)
        .sensoryFeedback(.success, trigger: saved)
    }

    private func save(_ on: Bool) {
        isSaving = true
        error = nil
        Task {
            defer { isSaving = false }
            do {
                try await session.update { apply(&$0, on) }
                saved.toggle()
            } catch {
                self.error = ErrorText.describe(error)
            }
        }
    }
}

/// An error at the top of a settings screen, where it is seen.
private struct ErrorSection: View {
    let error: String?
    var body: some View {
        if let error { Section { Text(error).foregroundStyle(.red) } }
    }
}

// MARK: Account

/// Name, username and email, saved with a button (a half-typed username must not be
/// sent), and the passkeys: ways to sign in, like the password.
struct AccountSettingsScreen: View {
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
            ErrorSection(error: error)
            if let user = session.user {
                fields(user)
                if Passkeys.available(for: APIClient.shared.baseURL) { passkeySection }
            }
        }
        .navigationTitle(L10n.t("settings.account"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: fill)
        .sensoryFeedback(.success, trigger: saved)
    }

    private func fields(_ user: UserResponse) -> some View {
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
            Button(action: saveAccount) {
                HStack {
                    Text(L10n.t("form.save")).bold()
                    if isSaving { Spacer(); ProgressView() }
                }
                .frame(minHeight: 44)
            }
            .disabled(!changed(user) || isSaving)
        } footer: {
            // Changing it breaks the old profile link and past mentions: said before, not after.
            if username.trimmingCharacters(in: .whitespaces) != user.username {
                Text(L10n.t("profile.usernameWarning"))
            } else {
                Text(L10n.t("profile.usernameRules"))
            }
        }
    }

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
                .confirmsDestructive(L10n.t("passkey.confirmDelete"),
                                     isPresented: Binding(get: { removing?.id == key.id }, set: { if !$0 { removing = nil } }),
                                     action: L10n.t("detail.delete")) { removePasskey(key) }
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
    }

    private func fill() {
        guard let user = session.user else { return }
        name = user.name
        username = user.username
        email = user.email ?? ""
    }

    private func changed(_ user: UserResponse) -> Bool {
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
        isSaving = true
        error = nil
        Task {
            defer { isSaving = false }
            do {
                try await session.update {
                    $0.name = name
                    $0.username = username
                    $0.email = email
                }
                fill()
                saved.toggle()
            } catch {
                self.error = ErrorText.describe(error)
            }
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
}

// MARK: Privacy

/// What others see of you, and a way to look at it as they do.
struct PrivacySettingsScreen: View {
    @Environment(SessionStore.self) private var session
    @State private var error: String?

    var body: some View {
        Form {
            ErrorSection(error: error)
            if let user = session.user {
                Section {
                    SettingSwitch(title: L10n.t("privacy.namePublic"), hint: L10n.t("privacy.namePublicHint"),
                                  value: user.namePublic ?? true, apply: { $0.namePublic = $1 }, error: $error)
                    SettingSwitch(title: L10n.t("privacy.emailPublic"), hint: L10n.t("privacy.emailPublicHint"),
                                  value: user.emailPublic ?? false, apply: { $0.emailPublic = $1 }, error: $error)
                } footer: {
                    Text(L10n.t("privacy.intro"))
                }
                Section {
                    NavigationLink(L10n.t("privacy.viewPublic")) { UserProfileScreen(handle: user.username) }
                        .frame(minHeight: 44)
                }
            }
        }
        .navigationTitle(L10n.t("privacy.title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: Notifications

/// Emails, notices on this iPhone and the "passing by" question.
struct NotificationsSettingsScreen: View {
    @Environment(SessionStore.self) private var session
    @State private var error: String?
    @State private var explainingMotion = false

    var body: some View {
        Form {
            ErrorSection(error: error)
            if let user = session.user {
                Section {
                    SettingSwitch(title: L10n.t("notif.weekly"), hint: L10n.t("notif.weeklyHint"),
                                  value: user.weeklyDigest ?? true, apply: { $0.weeklyDigest = $1 }, error: $error)
                    SettingSwitch(title: L10n.t("notif.mentions"), hint: L10n.t("notif.mentionsHint"),
                                  value: user.mentionEmails ?? true, apply: { $0.mentionEmails = $1 }, error: $error)
                }
                pushSection(user)
                passingBySection
            }
        }
        .navigationTitle(L10n.t("notif.title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Notices on this iPhone: the system's permission first, then which groups, as the
    /// web groups them. The groups only once it is on: asking which before saying yes is
    /// two decisions for nothing.
    @ViewBuilder private func pushSection(_ user: UserResponse) -> some View {
        let push = PushNotifications.shared
        Section {
            switch push.status {
            case .authorized, .provisional, .ephemeral:
                Label(L10n.t("ios.push.on"), systemImage: "bell.badge").frame(minHeight: 44)
                SettingSwitch(title: L10n.t("notif.pushFonts"), value: user.pushFontUpdates ?? true,
                              apply: { $0.pushFontUpdates = $1 }, error: $error)
                SettingSwitch(title: L10n.t("notif.pushMentions"), value: user.pushMentions ?? true,
                              apply: { $0.pushMentions = $1 }, error: $error)
                // Only to whoever really gets them.
                if user.isAdmin == true || user.canManageFonts {
                    SettingSwitch(title: L10n.t("notif.pushAdmin"), value: user.pushAdmin ?? true,
                                  apply: { $0.pushAdmin = $1 }, error: $error)
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
    private var passingBySection: some View {
        let passing = PassingBy.shared
        return Section {
            Toggle(isOn: Binding(get: { passing.isEnabled || explainingMotion }, set: { on in
                // Why the motion permission, before iOS asks it: said once, with the switch.
                if on, passing.needsMotionAsk { explainingMotion = true } else { Task { await passing.setEnabled(on) } }
            })) {
                Text(L10n.t("ios.passingBy.title"))
            }
            .frame(minHeight: 44)
            // Turned on before the question existed: offered here instead.
            if passing.isEnabled, passing.needsMotionAsk {
                Button(L10n.t("ios.passingBy.motionTitle")) { explainingMotion = true }.frame(minHeight: 44)
            }
            if passing.isBlocked {
                Text(L10n.t("ios.passingBy.needsAlways")).font(.subheadline).foregroundStyle(.secondary)
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    Link(L10n.t("ios.push.openSettings"), destination: url).frame(minHeight: 44)
                }
            }
        } footer: {
            Text(L10n.t("ios.passingBy.hint"))
        }
        .sheet(isPresented: $explainingMotion) {
            MotionExplainer { ask in
                explainingMotion = false
                Task {
                    if ask { await passing.askMotion() }
                    if !passing.isEnabled { await passing.setEnabled(true) }
                }
            }
            .presentationDetents([.medium, .large])
            .interactiveDismissDisabled()
        }
    }
}

/// Why "Motion & Fitness", told before iOS asks: without it, driving past a fountain
/// would ask about it, and nobody stops a car to look.
private struct MotionExplainer: View {
    let done: (_ ask: Bool) -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "car.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(L10n.t("ios.passingBy.motionTitle"))
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text(L10n.t("ios.passingBy.motionBody"))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button { done(true) } label: {
                Text(L10n.t("ios.passingBy.motionContinue")).frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            Button { done(false) } label: {
                Text(L10n.t("ios.passingBy.motionNotNow")).frame(maxWidth: .infinity, minHeight: 48)
            }
        }
        .padding(24)
    }
}

// MARK: Contribution

/// Whether your level and badges are seen, with what switching it off costs, told
/// before and not after.
struct ContributionSettingsScreen: View {
    @Environment(SessionStore.self) private var session
    @State private var error: String?

    var body: some View {
        Form {
            ErrorSection(error: error)
            if let user = session.user {
                let shared = !(user.gamificationOptOut ?? false)
                Section {
                    SettingSwitch(title: L10n.t("game.share"), value: shared,
                                  apply: { $0.gamificationOptOut = !$1 }, error: $error)
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.t("game.shareKeeps"))
                        if shared {
                            Text(L10n.t("game.shareOffHides"))
                            Text(L10n.t("game.shareOffCaps"))
                        }
                    }
                }
            }
        }
        .navigationTitle(L10n.t("game.title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
