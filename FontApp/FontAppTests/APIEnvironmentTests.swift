import Foundation
import Testing
@testable import FontApp

struct APIEnvironmentTests {
    @Test func theShortcutsAndFullAddresses() {
        #expect(APIEnvironment.server(from: "local") == APIEnvironment.local)
        #expect(APIEnvironment.server(from: " Production ") == APIEnvironment.production)
        #expect(APIEnvironment.server(from: "https://fontapp.fly.dev/")?.absoluteString == "https://fontapp.fly.dev")
        #expect(APIEnvironment.server(from: "http://127.0.0.1:8080")?.absoluteString == "http://127.0.0.1:8080")
    }

    @Test func aBareHostIsPlainHttpOnlyOnTheLocalNetwork() {
        #expect(APIEnvironment.server(from: "192.168.1.20:8080")?.absoluteString == "http://192.168.1.20:8080")
        #expect(APIEnvironment.server(from: "mac.local:8080")?.absoluteString == "http://mac.local:8080")
        #expect(APIEnvironment.server(from: "172.20.0.5")?.scheme == "http")
        #expect(APIEnvironment.server(from: "172.40.0.5")?.scheme == "https")
        #expect(APIEnvironment.server(from: "fontapp.fly.dev")?.absoluteString == "https://fontapp.fly.dev")
    }

    @Test func nonsenseIsNotAServer() {
        #expect(APIEnvironment.server(from: "") == nil)
        #expect(APIEnvironment.server(from: "   ") == nil)
        #expect(APIEnvironment.server(from: "ftp://example.com") == nil)
    }
}
