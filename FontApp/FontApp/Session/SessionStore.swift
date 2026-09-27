import Foundation
import Observation

/// Who is signed in. The token lives in the Keychain; the account is refreshed from
/// `/auth/me` at launch, which is also how a token revoked elsewhere is noticed.
@Observable
final class SessionStore {
    private(set) var user: UserResponse?

    var isSignedIn: Bool { user != nil || hasToken }
    var isStaff: Bool { user?.role?.isStaff ?? false }

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let keychain: TokenKeychain
    private var hasToken = false
    @ObservationIgnored private var observer: (any NSObjectProtocol)?

    init(api: APIClient = .shared) {
        self.api = api
        keychain = TokenKeychain(baseURL: api.baseURL)
        if let token = keychain.read() {
            api.credentials.set(token)
            hasToken = true
        }
        observer = NotificationCenter.default.addObserver(
            forName: Credentials.rejected, object: nil, queue: .main
        ) { [weak self] note in
            let token = note.object as? String
            MainActor.assumeIsolated { self?.tokenWasRejected(token) }
        }
    }

    /// Loads the account behind a stored token. A 401 signs out (via `rejected`); no
    /// network keeps the session, since the token is still good.
    func refresh() async {
        guard hasToken else { return }
        if let me = try? await api.me() { user = me }
    }

    func signIn(user name: String, password: String) async throws {
        let response = try await api.login(user: name, password: password)
        keychain.save(response.token)
        api.credentials.set(response.token)
        hasToken = true
        user = response.user
    }

    /// Revokes the token on the server when possible, and forgets it here in any case:
    /// signing out must work without signal.
    func signOut() async {
        try? await api.logout()
        clear()
    }

    private func tokenWasRejected(_ token: String?) {
        // A late 401 for a token already replaced by a new sign-in must not end it.
        guard let token, token == api.credentials.current else { return }
        clear()
    }

    private func clear() {
        keychain.delete()
        api.credentials.set(nil)
        hasToken = false
        user = nil
    }
}
