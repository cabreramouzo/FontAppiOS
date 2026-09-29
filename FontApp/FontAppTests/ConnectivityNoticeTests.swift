import Foundation
import Testing
@testable import FontApp

struct ConnectivityNoticeTests {
    private func input(online: Bool = true, pending: Int = 0, others: Int = 0, needsAuth: Bool = false,
                       sending: Bool = false, tried: Bool = false, justSynced: Bool = false) -> ConnectivityNotice.Input {
        .init(online: online, pending: pending, others: others, needsAuth: needsAuth,
              sending: sending, tried: tried, justSynced: justSynced)
    }

    @Test func nothingToSayOnlineWithNothingPending() {
        #expect(ConnectivityNotice.make(input()) == nil)
    }

    @Test func offlineWithNothingPendingInformsWithoutShouting() {
        let notice = ConnectivityNotice.make(input(online: false))
        #expect(notice?.titleKey == "offline.banner")
        #expect(notice?.tone == .neutral)
    }

    @Test func offlineWithPendingIsOrangeAndSaysItIsSafe() {
        let notice = ConnectivityNotice.make(input(online: false, pending: 2))
        #expect(notice?.titleKey == "offline.offlinePending")
        #expect(notice?.titleCount == 2)
        #expect(notice?.detailKey == "offline.savedSafe")
        #expect(notice?.tone == .warning)
    }

    @Test func onlineWithPendingSaysWhichProblemItIs() {
        #expect(ConnectivityNotice.make(input(pending: 1))?.detailKey == "offline.pendingHint")
        #expect(ConnectivityNotice.make(input(pending: 1, tried: true))?.detailKey == "offline.retryHint")
        #expect(ConnectivityNotice.make(input(pending: 1, needsAuth: true, tried: true))?.detailKey == "offline.needsLogin")
        // Another account's is the worse news, and beats the others.
        let others = ConnectivityNotice.make(input(pending: 3, others: 2, needsAuth: true, tried: true))
        #expect(others?.detailKey == "offline.otherAccount")
        #expect(others?.detailCount == 2)
    }

    @Test func sendingAndJustSynced() {
        #expect(ConnectivityNotice.make(input(pending: 2, sending: true))?.tone == .progress)
        #expect(ConnectivityNotice.make(input(pending: 2, sending: true))?.titleKey == "offline.syncing")
        let done = ConnectivityNotice.make(input(justSynced: true))
        #expect(done?.titleKey == "offline.synced")
        #expect(done?.tone == .success)
    }

    @Test func theCardShrinksEvenWithPendingButNotWhileItIsTransient() {
        #expect(ConnectivityNotice.mayShrink(input(pending: 3)))
        #expect(ConnectivityNotice.mayShrink(input(online: false)))
        #expect(!ConnectivityNotice.mayShrink(input(pending: 3, sending: true)))
        #expect(!ConnectivityNotice.mayShrink(input(justSynced: true)))
        #expect(!ConnectivityNotice.mayShrink(input()))
    }
}
