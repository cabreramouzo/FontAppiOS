import Foundation
import Testing
@testable import FontApp

extension StubbedNetwork {
@MainActor struct ProfileTests {
    // Shapes from the local backend on 28/09/2026 (seeded data, not real figures).
    private let game = """
    {"gotes":5437,"pending":5,"level":"river","nextLevel":"waterfall","gotesToNextLevel":1563,
    "impact":{"fontsWithPhotoThanksToYou":18,"fontsYouKeepFresh":23,"fontsYouPutOnTheMap":0},
    "mayorCount":3,"provisional":true,"badges":[],"byKind":[],"levels":[],"collection":[]}
    """
    private let guarded = """
    [{"source":"spring","stale":true,"days":387,"waterStatus":"unknown","fontID":"0F10538C-57A1-44AE-8AF2-9535A1F2E83C",
    "name":"Font de Bugader","lastCheck":"2025-09-05T12:28:37Z"}]
    """
    private let collection = #"{"visited":77,"types":[{"source":"tap","count":27},{"source":"well","count":0}],"local":{"nearby":30,"visited":7,"radiusKm":2.4}}"#
    private let comments = """
    [{"waterStatus":"flowing","fontID":"6F243559-5C20-4A18-82DF-D0D5C8369A75","createdAt":"2026-09-28T08:15:05Z",
    "id":"9ADC7F07-2A8A-4C34-9AE7-790E41DEFFA4","fontName":null,"body":"Mana bien"}]
    """

    @Test func everythingLoadsAndTheGameCanBeSwitchedOff() async {
        StubProtocol.sent = []
        StubProtocol.responses = [
            "GET /gamification/me": (200, game), "GET /gamification/guarded": (200, guarded),
            "GET /gamification/collection": (200, collection), "GET /auth/me/comments": (200, comments),
            "GET /auth/me/fonts": (200, "[]"), "GET /auth/me/favorites": (200, "[]"),
        ]
        let model = ProfileModel(api: StubProtocol.client())
        await model.load(near: (latitude: 41.81, longitude: 2.10))
        #expect(model.game?.gotes == 5437 && model.game?.mayorCount == 3)
        #expect(model.guarded?.first?.stale == true)
        #expect(model.collection?.local?.nearby == 30)
        #expect(model.comments?.first?.fontName == nil && model.fonts?.isEmpty == true)
        #expect(model.failed == nil)
        // The local goal is asked for with the position the app already had.
        #expect(StubProtocol.sent.contains { $0.path == "/gamification/collection" })

        // Switched off: 204 and nothing drawn; the lists stay.
        StubProtocol.responses["GET /gamification/me"] = (204, "")
        let off = ProfileModel(api: StubProtocol.client())
        await off.load()
        #expect(off.game == nil && off.comments?.count == 1)
    }

    @Test func noSignalKeepsWhatWasThere() async {
        StubProtocol.responses = [
            "GET /auth/me/comments": (200, comments), "GET /auth/me/fonts": (200, "[]"),
            "GET /auth/me/favorites": (200, "[]"), "GET /gamification/guarded": (200, guarded),
        ]
        let model = ProfileModel(api: StubProtocol.client())
        await model.load()
        StubProtocol.responses = ["GET /auth/me/comments": (-1, ""), "GET /auth/me/fonts": (-1, ""),
                                  "GET /auth/me/favorites": (-1, ""), "GET /gamification/guarded": (-1, "")]
        await model.load()
        #expect(model.comments?.count == 1 && model.guarded?.count == 1)
        #expect(model.failed != nil)
        model.clear()
        #expect(model.comments == nil && model.guarded == nil)
    }
}
}
