import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

/// Sign in with Google without Google's SDK: the OAuth code flow with PKCE in the system's
/// web sheet, then the ID token goes to `POST /auth/google`, as the web's does. The server
/// accepts tokens for this iOS client (`GOOGLE_IOS_CLIENT_ID`) as well as the web's.
@MainActor
enum GoogleSignIn {
    /// The OAuth client of type iOS for `net.fontapp.FontApp`. Public, not a secret.
    static let clientID = "665465134161-2rpp6kaubdssnetpvnm1vshlg22kd196.apps.googleusercontent.com"
    /// Google's redirect for an iOS client: the client ID reversed, as a URL scheme.
    static let scheme = "com.googleusercontent.apps.665465134161-2rpp6kaubdssnetpvnm1vshlg22kd196"
    private static var redirectURI: String { "\(scheme):/oauthredirect" }

    enum Failure: Error { case canceled, invalidResponse }

    /// Asks the person to choose a Google account; returns Google's signed ID token.
    static func idToken() async throws -> String {
        let verifier = randomString()
        let state = randomString()
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded()

        var auth = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        auth.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: "openid email profile"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
            .init(name: "prompt", value: "select_account"),
        ]

        let callback = try await present(auth.url!)
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == state,
              let code = items.first(where: { $0.name == "code" })?.value else {
            // Google sends `error=access_denied` when the person declines.
            if items.contains(where: { $0.name == "error" }) { throw Failure.canceled }
            throw Failure.invalidResponse
        }
        return try await exchange(code: code, verifier: verifier)
    }

    private static func present(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callback: .customScheme(scheme)) { url, error in
                if let url { continuation.resume(returning: url) }
                else if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                    continuation.resume(throwing: Failure.canceled)
                } else {
                    continuation.resume(throwing: error ?? Failure.invalidResponse)
                }
            }
            session.presentationContextProvider = PresentationAnchor.shared
            session.start()
        }
    }

    /// The code for the tokens. An iOS client has no secret: PKCE proves it is the same app.
    private static func exchange(code: String, verifier: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "code", value: code),
            .init(name: "code_verifier", value: verifier),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "grant_type", value: "authorization_code"),
        ]
        request.httpBody = Data((form.percentEncodedQuery ?? "").utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        struct Tokens: Decodable { let id_token: String }
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let tokens = try? JSONDecoder().decode(Tokens.self, from: data) else {
            throw Failure.invalidResponse
        }
        return tokens.id_token
    }

    private static func randomString() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded()
    }
}

/// The window the web sheet hangs from.
private final class PresentationAnchor: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = PresentationAnchor()
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}

private extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
