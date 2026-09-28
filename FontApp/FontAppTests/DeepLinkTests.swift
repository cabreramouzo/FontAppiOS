import Foundation
import Testing
@testable import FontApp

struct DeepLinkTests {
    @Test func aFountainOrAProfileOnTheSite() {
        let id = UUID()
        #expect(DeepLink(URL(string: "https://fontapp.net/fonts/\(id.uuidString)?lang=es")!) == .fountain(id))
        #expect(DeepLink(URL(string: "https://fontapp.net/users/marta_r")!) == .profile("marta_r"))
    }

    @Test func anythingElseIsNotOpened() {
        #expect(DeepLink(URL(string: "https://fontapp.net/fonts/not-an-id")!) == nil)
        #expect(DeepLink(URL(string: "https://fontapp.net/zones")!) == nil)
        #expect(DeepLink(URL(string: "https://example.com/fonts/\(UUID().uuidString)")!) == nil)
    }
}
