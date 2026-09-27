import SwiftUI

/// Creating an account, natively. Same fields and rules as the web's register page; on
/// success the account is signed in at once.
struct SignUpView: View {
    /// Called once signed in, so the sign-in sheet can close too.
    let onDone: () -> Void

    @Environment(SessionStore.self) private var session
    @State private var name = ""
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isSending = false
    @State private var error: String?
    @FocusState private var field: Field?

    private enum Field { case name, username, email, password }

    var body: some View {
        Form {
            Section {
                TextField(L10n.t("login.name"), text: $name)
                    .textContentType(.name)
                    .focused($field, equals: .name)
                    .submitLabel(.next)
                    .onSubmit { field = .username }
                TextField(L10n.t("login.username"), text: $username)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($field, equals: .username)
                    .submitLabel(.next)
                    .onSubmit { field = .email }
            } footer: {
                // Said before sending: the username is public and signs every review.
                Text(L10n.t(username.contains("@") ? "profile.usernameNotEmail" : "profile.usernameRules"))
            }
            Section {
                TextField(L10n.t("login.email"), text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($field, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { field = .password }
                // .newPassword lets iOS suggest a strong password and save it in Passwords.
                SecureField(L10n.t("login.password"), text: $password)
                    .textContentType(.newPassword)
                    .focused($field, equals: .password)
                    .submitLabel(.join)
                    .onSubmit(submit)
            }
            if let error {
                Section { Text(error).foregroundStyle(.red) }
            }
            Section {
                Button(action: submit) {
                    HStack {
                        Text(L10n.t("login.register")).bold()
                        if isSending { Spacer(); ProgressView() }
                    }
                    .frame(minHeight: 44)
                }
                .disabled(isSending)
            }
        }
        .navigationTitle(L10n.t("login.createAccount"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { field = .name }
    }

    private func submit() {
        guard !isSending else { return }
        if let problem = SignUpRules.problem(name: name, username: username, email: email, password: password) {
            error = message(for: problem)
            return
        }
        error = nil
        isSending = true
        let account = NewAccount(name: name.trimmingCharacters(in: .whitespaces),
                                 username: username.trimmingCharacters(in: .whitespaces),
                                 email: email.trimmingCharacters(in: .whitespaces),
                                 password: password, lang: SignUpRules.webLanguage())
        Task {
            defer { isSending = false }
            do {
                try await session.signUp(account)
                onDone()
            } catch {
                // Taken username or email come with their code and are translated.
                self.error = ErrorText.describe(error)
            }
        }
    }

    private func message(for problem: SignUpRules.Problem) -> String {
        switch problem {
        case .nameEmpty: L10n.t("profile.nameEmpty")
        case .usernameIsEmail: L10n.t("profile.usernameNotEmail")
        case .usernameInvalid: L10n.t("profile.usernameRules")
        case .emailInvalid: L10n.t("ios.signUp.emailInvalid")
        case .passwordShort: L10n.t("ios.signUp.passwordShort")
        }
    }
}
