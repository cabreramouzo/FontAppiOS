import Foundation
import Testing
@testable import FontApp

extension StubbedNetwork {
@MainActor struct AccountDeletionTests {
    private let me = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
    private var login: String {
        #"{"token":"t0k","expiresAt":"2027-03-28T00:00:00Z","user":{"id":"\#(me.uuidString)","name":"Prova","username":"prova_ios","role":"user"}}"#
    }

    @Test func deletingForgetsTheSessionOnlyWhenTheServerAgrees() async throws {
        let api = StubProtocol.client()
        let path = "DELETE /users/\(me.uuidString)"
        StubProtocol.responses = ["POST /auth/login": (200, login), path: (-1, "")]
        let session = SessionStore(api: api)
        try await session.signIn(user: "prova_ios", password: "x")

        // No signal: nothing is forgotten, the account is still there.
        await #expect(throws: APIError.self) { try await session.deleteAccount() }
        #expect(session.isSignedIn && session.userID == me)

        StubProtocol.responses[path] = (204, "")
        try await session.deleteAccount()
        #expect(!session.isSignedIn && session.userID == nil)
        #expect(api.credentials.current == nil)
    }

    @Test func itsContributionsLeftOnThePhoneGo() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "outbox-\(UUID().uuidString)")
        let box = Outbox(directory: dir, api: StubProtocol.client())
        let review = NewReview(waterStatus: "flowing", confirmIfUnchanged: true, remoteDistanceM: nil)
        box.currentUserID = me
        box.enqueueReview(review, fontID: UUID(), fontName: nil)
        box.currentUserID = UUID()
        box.enqueueReview(review, fontID: UUID(), fontName: nil)
        box.discard(queuedBy: me)
        #expect(box.items.count == 1 && box.items.first?.userID != me)
    }
}
}
