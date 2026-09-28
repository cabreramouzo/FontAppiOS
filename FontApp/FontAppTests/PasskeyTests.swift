import Foundation
import Testing
@testable import FontApp

struct PasskeyTests {
    @Test func base64urlRoundTripsWithoutPadding() {
        let bytes = Data([0xfb, 0xff, 0xbf, 0x00, 0x3e])
        let text = Passkeys.encode(bytes)
        #expect(!text.contains("=") && !text.contains("+") && !text.contains("/"))
        #expect(Passkeys.decode(text) == bytes)
        // The server's challenge, as it sends it.
        #expect(Passkeys.decode("g1s_5AXufyeLKPz5UO-4gzjmNt60-lx-W1XH2owPpnE")?.count == 32)
    }

    @Test func readsTheServersOptions() throws {
        let json = #"{"requestID":"1E86626C-A567-40A8-8C06-586EE5C6F3A7","existingCredentialIDs":[],"publicKey":{"user":{"id":"N0E2","name":"xavi","displayName":"X"},"challenge":"g1s_","rp":{"id":"fontapp.net","name":"FontApp"}}}"#
        let start = try JSONDecoder().decode(Passkeys.Start<Passkeys.CreationOptions>.self, from: Data(json.utf8))
        #expect(start.publicKey.rp.id == "fontapp.net")
        #expect(start.publicKey.user.name == "xavi")
    }

    @Test func sendsTheCredentialAsTheWebDoes() throws {
        let credential = Passkeys.Credential(id: Data([1, 2, 3]), response: .init(
            clientDataJSON: "e30", authenticatorData: "AA", signature: "AQ", userHandle: nil))
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(credential)) as? [String: Any])
        #expect(object["id"] as? String == "AQID")
        #expect(object["rawId"] as? String == "AQID")
        #expect(object["type"] as? String == "public-key")
        let response = try #require(object["response"] as? [String: Any])
        #expect(response["signature"] as? String == "AQ")
        #expect(response["attestationObject"] == nil)
    }

    @Test func onlyAgainstARealServer() {
        #expect(Passkeys.available(for: URL(string: "https://fontapp.fly.dev")!))
        #expect(!Passkeys.available(for: URL(string: "http://127.0.0.1:8080")!))
        #expect(!Passkeys.available(for: URL(string: "http://192.168.1.20:8080")!))
    }
}
