import Foundation
import Testing
@testable import FontApp

struct SignUpRulesTests {
    private func problem(name: String = "Ada", username: String = "ada_l", email: String = "ada@example.com",
                         password: String = "password1") -> SignUpRules.Problem? {
        SignUpRules.problem(name: name, username: username, email: email, password: password)
    }

    @Test func aValidAccountPasses() {
        #expect(problem() == nil)
        #expect(problem(username: "a.b-c_9") == nil)
    }

    @Test func theServersUsernameRule() {
        // An email in the username is said on its own: it would sign every review.
        #expect(problem(username: "ada@example.com") == .usernameIsEmail)
        #expect(problem(username: "ab") == .usernameInvalid)
        #expect(problem(username: "josé") == .usernameInvalid)
        #expect(problem(username: "ada lovelace") == .usernameInvalid)
        #expect(problem(username: String(repeating: "a", count: 31)) == .usernameInvalid)
    }

    @Test func theOtherFields() {
        #expect(problem(name: "  ") == .nameEmpty)
        #expect(problem(email: "ada@example") == .emailInvalid)
        #expect(problem(password: "short77") == .passwordShort)
    }

    @Test func theWelcomeEmailLanguage() {
        #expect(SignUpRules.webLanguage("pt-PT") == "pt")
        #expect(SignUpRules.webLanguage("ca") == "ca")
        #expect(SignUpRules.webLanguage("de") == nil)
    }
}
