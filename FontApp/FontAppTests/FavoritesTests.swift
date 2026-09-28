import Foundation
import Testing
@testable import FontApp

extension StubbedNetwork {
@MainActor struct FavoritesTests {
    private let me = UUID(), other = UUID()
    private let fontID = UUID(uuidString: "6F243559-5C20-4A18-82DF-D0D5C8369A75")!
    private var list: String {
        #"[{"id":"\#(fontID.uuidString)","name":"Font del Molí","latitude":41.8,"longitude":2.1,"municipality":"Moià"}]"#
    }

    private func defaults() -> UserDefaults {
        let name = "favorites-\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }

    @Test func theListIsKeptPerAccountForWhenThereIsNoSignal() async {
        StubProtocol.responses = ["GET /auth/me/favorites": (200, list)]
        let store = defaults()
        let favorites = Favorites(api: StubProtocol.client(), defaults: store)
        favorites.sessionChanged(to: me)
        await favorites.reload()
        #expect(favorites.contains(fontID) && favorites.items.first?.municipality == "Moià")

        // Another account never sees it; back to the first one, it is there before any load.
        favorites.sessionChanged(to: other)
        #expect(favorites.items.isEmpty)
        StubProtocol.responses["GET /auth/me/favorites"] = (-1, "")
        let reopened = Favorites(api: StubProtocol.client(), defaults: store)
        reopened.sessionChanged(to: me)
        #expect(reopened.contains(fontID))
        await reopened.reload()
        #expect(reopened.contains(fontID))
        if case .failed = reopened.state {} else { Issue.record("expected a failed state") }
    }

    @Test func starringIsImmediateAndUndoneIfTheServerSaysNo() async throws {
        let font = try APIClient.decoder.decode([FontSummary].self, from: Data(list.utf8))[0]
        let path = "/fonts/\(fontID.uuidString)/favorite"
        StubProtocol.sent = []
        StubProtocol.responses = ["POST \(path)": (200, #"{"favorited":true,"count":1}"#)]
        let favorites = Favorites(api: StubProtocol.client(), defaults: defaults())
        favorites.sessionChanged(to: me)
        try await favorites.toggle(font)
        #expect(favorites.contains(fontID))
        #expect(StubProtocol.sent.contains { $0.method == "POST" && $0.path == path })

        StubProtocol.responses["DELETE \(path)"] = (-1, "")
        await #expect(throws: APIError.self) { try await favorites.toggle(font) }
        #expect(favorites.contains(fontID))
    }
}
}
