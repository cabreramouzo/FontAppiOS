import AuthenticationServices
import SwiftUI

/// Username (or email) and password, Apple, Google or a passkey, and the way to create an account. Password
/// recovery stays on the web: it works through a link sent by email.
struct SignInView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var user = ""
    @State private var password = ""
    @State private var isSending = false
    @State private var error: String?
    @FocusState private var field: Field?

    private enum Field { case user, password }

    var body: some View {
        NavigationStack {
            // Same order as the web's login page: the one-tap providers first, then the
            // password form, then the links.
            ScrollView {
                VStack(spacing: 16) {
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        apple(result)
                    }
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    .frame(height: 48)
                    .disabled(isSending)
                    GoogleButton(action: google)
                        .disabled(isSending)
                    if Passkeys.available(for: APIClient.shared.baseURL) {
                        Button(action: passkey) {
                            Label(L10n.t("passkey.login"), systemImage: "person.badge.key")
                                .frame(maxWidth: .infinity, minHeight: 36)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isSending)
                    }
                    divider
                    VStack(alignment: .leading, spacing: 4) {
                        TextField(L10n.t("login.userLabel"), text: $user)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($field, equals: .user)
                            .submitLabel(.next)
                            .onSubmit { field = .password }
                            .modifier(FieldBox())
                        Text(L10n.t("login.userOrEmailHint"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    SecureField(L10n.t("login.password"), text: $password)
                        .textContentType(.password)
                        .focused($field, equals: .password)
                        .submitLabel(.go)
                        .onSubmit(submit)
                        .modifier(FieldBox())
                    Button(action: submit) {
                        HStack(spacing: 8) {
                            Text(L10n.t("login.enter")).bold()
                            if isSending { ProgressView() }
                        }
                        .frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSubmit)
                    if let error {
                        Text(error)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        // Resetting needs the link the server emails, which opens the web.
                        Link(L10n.t("login.forgot"), destination: web("forgot-password"))
                            .frame(minHeight: 44)
                        HStack(spacing: 4) {
                            Text(L10n.t("login.noAccount")).foregroundStyle(.secondary)
                            NavigationLink(L10n.t("login.signup")) {
                                SignUpView { dismiss() }
                            }
                        }
                        .frame(minHeight: 44)
                        LegalLink()
                        #if DEBUG
                        NavigationLink {
                            Form { ServerPicker() }
                        } label: {
                            Text(verbatim: "API server: \(APIClient.shared.baseURL.host() ?? "")")
                                .font(.caption.monospaced())
                                .frame(minHeight: 44)
                        }
                        #endif
                    }
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(20)
                .frame(maxWidth: 400)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
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

    /// The web's "— or —" between the providers and the password form.
    private var divider: some View {
        HStack(spacing: 12) {
            VStack { Divider() }
            Text(L10n.t("login.or")).font(.footnote).foregroundStyle(.secondary)
            VStack { Divider() }
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

    private func apple(_ result: Result<ASAuthorization, any Error>) {
        switch result {
        case .failure(let error):
            // Closing Apple's sheet is not an error worth a red sentence.
            if (error as? ASAuthorizationError)?.code != .canceled { self.error = ErrorText.describe(error) }
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
            isSending = true
            error = nil
            Task {
                defer { isSending = false }
                do {
                    try await session.signInWithApple(credential)
                    dismiss()
                } catch {
                    self.error = ErrorText.describe(error)
                }
            }
        }
    }

    private func google() {
        isSending = true
        error = nil
        Task {
            defer { isSending = false }
            do {
                try await session.signInWithGoogle()
                dismiss()
            } catch GoogleSignIn.Failure.canceled {
                // Closing Google's sheet is not an error either.
            } catch GoogleSignIn.Failure.invalidResponse {
                error = L10n.t("login.googleUnavailable")
            } catch {
                self.error = ErrorText.describe(error)
            }
        }
    }

    private func passkey() {
        isSending = true
        error = nil
        Task {
            defer { isSending = false }
            do {
                try await session.signInWithPasskey()
                dismiss()
            } catch where PasskeySheet.wasCancelled(error) {
                // Also what the sheet answers when this iPhone has no passkey for FontApp.
                self.error = L10n.t("passkey.cancelled")
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

/// A rounded, outlined text field like the web's.
private struct FieldBox: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .frame(minHeight: 48)
            .background(.background, in: .rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
    }
}

/// Google's branded "Continue with Google" button: the colour "G" on a neutral, outlined
/// pill, in the light and dark variants their sign-in branding guidelines allow.
private struct GoogleButton: View {
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let dark = colorScheme == .dark
        Button(action: action) {
            HStack(spacing: 10) {
                Image("GoogleG").resizable().frame(width: 20, height: 20)
                Text(L10n.t("ios.login.google")).font(.body.weight(.medium))
            }
            .foregroundStyle(Color(hex: dark ? 0xE3E3E3 : 0x1F1F1F))
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Color(hex: dark ? 0x131314 : 0xFFFFFF), in: .capsule)
            .overlay(Capsule().strokeBorder(Color(hex: dark ? 0x8E918F : 0x747775)))
            .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
    }
}
