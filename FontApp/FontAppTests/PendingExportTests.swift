import Foundation
import Testing
@testable import FontApp

struct PendingExportTests {
    private let fontID = UUID()

    private func item(_ kind: OutboxItem.Kind, queuedAt: Date = Date(timeIntervalSince1970: 1_000), attempts: Int = 0,
                      review: NewReview? = nil, newFont: NewFont? = nil, status: String? = nil,
                      comment: ComposedReview? = nil, photo: String? = nil) -> OutboxItem {
        OutboxItem(id: UUID(), kind: kind, fontID: fontID, fontName: "Font del Faig", userID: nil, queuedAt: queuedAt,
                   attempts: attempts, needsAuth: false, review: review, photoFile: photo, photoMeta: nil,
                   newFont: newFont, firstStatus: status, comment: comment)
    }

    private func decode(_ json: String) throws -> [[String: Any]] {
        try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])
    }

    @Test func theCopiedTextIsForAPersonAndNotForAProgram() {
        let font = NewFont(name: "Font nova", latitude: 41.8, longitude: 2.1, image: nil, description: "Darrere el quiosc",
                           source: .fountain, drinkable: .yes, allowNearbyDuplicate: nil)
        let text = PendingExport.text([item(.font, attempts: 2, newFont: font, status: "flowing", photo: "x.jpg")])
        #expect(text.contains("Font nova"))
        #expect(text.contains("41.80000, 2.10000"))
        #expect(text.contains("Darrere el quiosc"))
        #expect(text.contains("maps.apple.com/?ll=41.80000,2.10000"))
        // Nothing that is a key, a file or an id.
        #expect(!text.contains("{") && !text.contains("hasPhoto") && !text.contains("new-fountain"))
        #expect(!text.contains("x.jpg"))
        #expect(!text.contains(fontID.uuidString))
    }

    @Test func aReviewReadsAsLabelsAndValuesWithoutTheFountainId() {
        let review = NewReview(waterStatus: "dry", confirmIfUnchanged: true, remoteDistanceM: nil)
        let text = PendingExport.text([item(.review, review: review)])
        #expect(text.contains("Font del Faig"))
        #expect(!text.contains(fontID.uuidString))
        #expect(!text.contains("waterStatus"))
    }

    @Test func severalContributionsAreSeparatedByABlankLine() {
        let review = NewReview(waterStatus: "dry", confirmIfUnchanged: true, remoteDistanceM: nil)
        let text = PendingExport.text([item(.review, review: review), item(.review, review: review)])
        #expect(text.components(separatedBy: "\n\n").count == 2)
    }

    @Test func rowsShowOnlyWhatCarriesSomething() {
        let comment = ComposedReview(waterStatus: nil, rating: 4, body: "", image: nil)
        let rows = PendingExport.rows(of: item(.comment, comment: comment))
        #expect(rows.count == 3) // name, rating, fountain id: no empty text, no status
        #expect(rows.contains { $0.value == "4" })
    }

    @Test func theListIsOldestFirst() {
        let old = item(.photo, queuedAt: Date(timeIntervalSince1970: 1))
        let new = item(.photo, queuedAt: Date(timeIntervalSince1970: 9))
        #expect(PendingExport.inQueueOrder([new, old]).map(\.id) == [old.id, new.id])
    }
}

struct OutboxDiscardTests {
    private func outbox() -> Outbox {
        Outbox(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
    }

    private func review(_ outbox: Outbox, as user: UUID?) {
        outbox.currentUserID = user
        outbox.enqueueReview(NewReview(waterStatus: "flowing", confirmIfUnchanged: true, remoteDistanceM: nil),
                             fontID: UUID(), fontName: nil)
    }

    @Test func nothingPendingOffersNothing() {
        #expect(outbox().discardPlan == nil)
    }

    @Test func aMixedQueueDiscardsOnlyTheOtherAccountsAndKeepsMine() {
        let box = outbox()
        let a = UUID(), b = UUID()
        review(box, as: a)
        review(box, as: b)
        review(box, as: b)
        #expect(box.discardPlan == Outbox.DiscardPlan(onlyOthers: true, count: 1))
        box.discard(onlyOthers: true)
        #expect(box.items.count == 2)
        #expect(box.items.allSatisfy { $0.userID == b })
    }

    @Test func aQueueOfOneKindDiscardsAll() {
        let box = outbox()
        review(box, as: UUID())
        review(box, as: box.currentUserID)
        #expect(box.discardPlan == Outbox.DiscardPlan(onlyOthers: false, count: 2))
        box.discard()
        #expect(box.items.isEmpty)
    }
}
