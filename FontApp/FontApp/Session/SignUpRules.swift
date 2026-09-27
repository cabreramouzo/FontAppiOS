import Foundation

/// What the sign-up form checks before sending, with the server's own rules.
///
/// Checked here and not only on the server, as the web does (`RegisterPage.tsx`): the
/// server answers in Spanish, and an error that arrives after sending makes one fill the
/// form again to fix a letter. The username rule is the server's (`Mentions.isMentionable`)
/// on purpose: a name the server accepted and mentions could not parse would send
/// notifications to someone else.
nonisolated enum SignUpRules {
    enum Problem: Equatable {
        case nameEmpty
        /// An "@" in the username: it is public and signs every review, so no email there.
        case usernameIsEmail
        case usernameInvalid
        case emailInvalid
        case passwordShort
    }

    static let minPassword = 8

    static func problem(name: String, username: String, email: String, password: String) -> Problem? {
        if name.trimmingCharacters(in: .whitespaces).isEmpty { return .nameEmpty }
        let user = username.trimmingCharacters(in: .whitespaces)
        if user.contains("@") { return .usernameIsEmail }
        if user.range(of: "^[a-zA-Z0-9_.-]{3,30}$", options: .regularExpression) == nil { return .usernameInvalid }
        let mail = email.trimmingCharacters(in: .whitespaces)
        if mail.range(of: "^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", options: .regularExpression) == nil { return .emailInvalid }
        if password.count < minPassword { return .passwordShort }
        return nil
    }

    /// The app's language as the web names it, for the welcome email.
    static func webLanguage(_ localization: String? = Bundle.main.preferredLocalizations.first) -> String? {
        guard let localization else { return nil }
        let code = String(localization.prefix(2))
        return ["ca", "es", "gl", "eu", "en", "fr", "pt", "it"].contains(code) ? code : nil
    }
}
