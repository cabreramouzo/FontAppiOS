import SwiftUI

/// Username (or email) and password, and the way to create an account. Password
/// recovery stays on the web: it works through a link sent by email.
struct SignInView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var user = ""
    @State private var password = ""
    @State private var isSending = false
    @State private var error: String?
    @FocusState private var field: Field?

    private enum Field { case user, password }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L10n.t("login.userLabel"), text: $user)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($field, equals: .user)
                        .submitLabel(.next)
                        .onSubmit { field = .password }
                    SecureField(L10n.t("login.password"), text: $password)
                        .textContentType(.password)
                        .focused($field, equals: .password)
                        .submitLabel(.go)
                        .onSubmit(submit)
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.t("login.userOrEmailHint"))
                        #if DEBUG
                        // Which backend this build signs in to. A Debug build on a phone
                        // talks to 127.0.0.1, the phone itself: without this line that
                        // looks like "login does nothing" (see docs/local-testing.md).
                        Text(verbatim: "Debug · \(APIClient.shared.baseURL.absoluteString)")
                            .font(.caption.monospaced())
                        #endif
                    }
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
                Section {
                    Button(action: submit) {
                        HStack {
                            Text(L10n.t("login.enter")).bold()
                            if isSending { Spacer(); ProgressView() }
                        }
                        .frame(minHeight: 44)
                    }
                    .disabled(!canSubmit)
                }
                Section {
                    NavigationLink(L10n.t("login.noAccount") + L10n.t("login.signup")) {
                        SignUpView { dismiss() }
                    }
                    // Resetting needs the link the server emails, which opens the web.
                    Link(L10n.t("login.forgot"), destination: web("forgot-password"))
                }
            }
            .navigationTitle(L10n.t("login.enter"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .close) { dismiss() }
                }
            }
            .onAppear { field = .user }
        }
    }

    private var canSubmit: Bool {
        !isSending && !user.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
    }

    private func submit() {
        guard canSubmit else { return }
        isSending = true
        error = nil
        Task {
            defer { isSending = false }
            do {
                try await session.signIn(user: user.trimmingCharacters(in: .whitespaces), password: password)
                dismiss()
            } catch let e as APIError where e.status == 401 {
                error = L10n.t("login.badCredentials")
            } catch {
                self.error = ErrorText.describe(error)
            }
        }
    }

    private func web(_ path: String) -> URL {
        URL(string: "https://fontapp.net/\(path)")!
    }
}
