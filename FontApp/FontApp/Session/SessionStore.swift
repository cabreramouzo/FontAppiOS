import Foundation
import Observation

/// Who is signed in. The token lives in the Keychain; the account is refreshed from
/// `/auth/me` at launch, which is also how a token revoked elsewhere is noticed.
@Observable
final class SessionStore {
    private(set) var user: UserResponse?

    var isSignedIn: Bool { user != nil || hasToken }
    var isStaff: Bool { user?.role?.isStaff ?? false }
    /// Known as soon as the app starts, before `/auth/me` answers (or without signal):
    /// the outbox needs it to send each contribution only under the account that made it.
    private(set) var userID: UUID?

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
            userID = UserDefaults.standard.string(forKey: userKey).flatMap(UUID.init(uuidString:))
            // The last known account, so name and staff colours are there without signal.
            user = UserDefaults.standard.data(forKey: accountKey)
                .flatMap { try? JSONDecoder().decode(UserResponse.self, from: $0) }
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
        if let me = try? await api.me() { setUser(me) }
    }

    func signIn(user name: String, password: String) async throws {
        start(try await api.login(user: name, password: password))
    }

    /// Face ID and no password: the system offers the account's passkey.
    func signInWithPasskey() async throws {
        start(try await PasskeySheet.signIn(api: api))
    }

    private func start(_ response: LoginResponse) {
        keychain.save(response.token)
        api.credentials.set(response.token)
        hasToken = true
        setUser(response.user)
    }

    private var userKey: String { "session.userID.\(keychain.account)" }
    private var accountKey: String { "session.account.\(keychain.account)" }

    private func setUser(_ user: UserResponse) {
        self.user = user
        userID = user.id
        UserDefaults.standard.set(user.id.uuidString, forKey: userKey)
        UserDefaults.standard.set(try? JSONEncoder().encode(user), forKey: accountKey)
    }

    /// Creates the account and signs in with it, as the web does.
    func signUp(_ account: NewAccount) async throws {
        _ = try await api.register(account)
        try await signIn(user: account.username, password: account.password)
    }

    /// Revokes the token on the server when possible, and forgets it here in any case:
    /// signing out must work without signal.
    func signOut() async {
        // First, while the token still authenticates: this phone stops getting the
        // account's notices.
        await PushNotifications.shared.signingOut()
        try? await api.logout()
        clear()
    }

    /// Saves a change to the account and keeps the server's answer as the account.
    func update(_ change: (inout ProfileUpdate) -> Void) async throws {
        guard let user else { return }
        var update = ProfileUpdate(user)
        change(&update)
        setUser(try await api.updateProfile(user.id, update))
    }

    /// Deletes (anonymises) the account on the server, then forgets it here. Unlike
    /// signing out it needs signal: nothing is forgotten until the server has agreed.
    func deleteAccount() async throws {
        guard let userID else { return }
        try await api.deleteAccount(userID)
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
        userID = nil
        UserDefaults.standard.removeObject(forKey: userKey)
        UserDefaults.standard.removeObject(forKey: accountKey)
    }
}
