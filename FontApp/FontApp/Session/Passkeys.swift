import AuthenticationServices
import Foundation
import UIKit

/// Passkeys, as the web's (`/auth/passkeys/*`): sign in with Face ID and no password,
/// and add or remove them in the settings. The server speaks WebAuthn JSON; the system
/// sheet speaks bytes, so this file only converts between the two.
///
/// The relying party is `fontapp.net`, the web's: a passkey made on the web works here
/// and the other way round. That needs the `webcredentials:fontapp.net` entitlement and
/// the web's apple-app-site-association file, so it only works against production. A
/// local server's relying party is `localhost`, which no app can claim.
nonisolated struct PasskeySummary: Decodable, Identifiable, Sendable {
    let id: UUID
    let label: String
    let createdAt: Date?
    let lastUsedAt: Date?
}

nonisolated enum Passkeys {
    /// Hidden against a local server, where the system sheet could only fail.
    static func available(for baseURL: URL) -> Bool {
        guard let host = baseURL.host() else { return false }
        return !(host == "localhost" || host.hasSuffix(".local") || host.hasPrefix("127.")
                 || host.hasPrefix("10.") || host.hasPrefix("192.168.") || host == "::1")
    }

    /// base64url without padding, as WebAuthn JSON carries every byte string.
    static func decode(_ text: String) -> Data? {
        var s = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        s += String(repeating: "=", count: (4 - s.count % 4) % 4)
        return Data(base64Encoded: s)
    }

    static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // What the server sends: only the fields the system sheet needs.
    struct RequestOptions: Decodable, Sendable { let challenge: String; let rpId: String }
    struct CreationOptions: Decodable, Sendable {
        struct RP: Decodable, Sendable { let id: String }
        struct User: Decodable, Sendable { let id: String; let name: String }
        let challenge: String
        let rp: RP
        let user: User
    }
    struct Start<Options: Decodable & Sendable>: Decodable, Sendable {
        let requestID: UUID
        let publicKey: Options
        let existingCredentialIDs: [String]?
    }

    /// The credential as the web's `credentialJSON` builds it.
    struct Credential: Encodable, Sendable {
        struct Response: Encodable, Sendable {
            let clientDataJSON: String
            var attestationObject: String?
            var transports: [String]?
            var authenticatorData: String?
            var signature: String?
            var userHandle: String?
        }
        let id: String
        let rawId: String
        let type = "public-key"
        let authenticatorAttachment = "platform"
        let clientExtensionResults: [String: String] = [:]
        let response: Response

        init(id: Data, response: Response) {
            self.id = Passkeys.encode(id)
            rawId = self.id
            self.response = response
        }
    }
}

/// One system passkey sheet, awaited. Kept alive by the caller until it answers.
@MainActor
final class PasskeySheet: NSObject, ASAuthorizationControllerDelegate,
                          ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<ASAuthorization, any Error>?

    func run(_ request: ASAuthorizationRequest) async throws -> ASAuthorization {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        continuation?.resume(returning: authorization)
        continuation = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: any Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }

    /// Signs in: the system offers every FontApp passkey on this iPhone (or a nearby
    /// device's, by QR), so no username is asked first.
    static func signIn(api: APIClient) async throws -> LoginResponse {
        let start: Passkeys.Start<Passkeys.RequestOptions> = try await api.passkeyLoginOptions()
        guard let challenge = Passkeys.decode(start.publicKey.challenge) else { throw PasskeyError.badOptions }
        let request = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: start.publicKey.rpId)
            .createCredentialAssertionRequest(challenge: challenge)
        request.userVerificationPreference = .required
        let sheet = PasskeySheet()
        guard let assertion = try await sheet.run(request).credential
            as? ASAuthorizationPlatformPublicKeyCredentialAssertion else { throw PasskeyError.badOptions }
        let credential = Passkeys.Credential(id: assertion.credentialID, response: .init(
            clientDataJSON: Passkeys.encode(assertion.rawClientDataJSON),
            authenticatorData: Passkeys.encode(assertion.rawAuthenticatorData),
            signature: Passkeys.encode(assertion.signature),
            userHandle: assertion.userID.isEmpty ? nil : Passkeys.encode(assertion.userID)))
        return try await api.passkeyLogin(requestID: start.requestID, credential: credential)
    }

    /// Adds a passkey to the signed-in account.
    static func add(label: String, api: APIClient) async throws -> PasskeySummary {
        let start: Passkeys.Start<Passkeys.CreationOptions> = try await api.passkeyRegistrationOptions()
        let options = start.publicKey
        guard let challenge = Passkeys.decode(options.challenge),
              let userID = Passkeys.decode(options.user.id) else { throw PasskeyError.badOptions }
        let request = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: options.rp.id)
            .createCredentialRegistrationRequest(challenge: challenge, name: options.user.name, userID: userID)
        request.userVerificationPreference = .required
        // Not the same passkey twice: the system says so instead of making a second one.
        request.excludedCredentials = (start.existingCredentialIDs ?? []).compactMap(Passkeys.decode)
            .map(ASAuthorizationPlatformPublicKeyCredentialDescriptor.init(credentialID:))
        let sheet = PasskeySheet()
        guard let registration = try await sheet.run(request).credential
            as? ASAuthorizationPlatformPublicKeyCredentialRegistration,
              let attestation = registration.rawAttestationObject else { throw PasskeyError.badOptions }
        let credential = Passkeys.Credential(id: registration.credentialID, response: .init(
            clientDataJSON: Passkeys.encode(registration.rawClientDataJSON),
            attestationObject: Passkeys.encode(attestation),
            transports: ["internal", "hybrid"]))
        return try await api.passkeyRegister(requestID: start.requestID, label: label, credential: credential)
    }

    /// Closing the sheet is not an error worth a red sentence.
    static func wasCancelled(_ error: any Error) -> Bool {
        (error as? ASAuthorizationError)?.code == .canceled
    }
}

nonisolated enum PasskeyError: Error { case badOptions }
