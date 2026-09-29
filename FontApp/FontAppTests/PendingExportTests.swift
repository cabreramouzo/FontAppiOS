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

    @Test func aNewFountainExportsItsFieldsAndNeverItsPhoto() throws {
        let font = NewFont(name: "Font nova", latitude: 41.8, longitude: 2.1, image: nil, description: "Darrere el quiosc",
                           source: .fountain, drinkable: .yes, allowNearbyDuplicate: nil)
        let list = try decode(PendingExport.json([item(.font, attempts: 2, newFont: font, status: "flowing", photo: "x.jpg")]))
        let out = try #require(list.first)
        #expect(out["type"] as? String == "new-fountain")
        #expect(out["name"] as? String == "Font nova")
        #expect(out["latitude"] as? Double == 41.8)
        #expect(out["waterStatus"] as? String == "flowing")
        #expect(out["hasPhoto"] as? Bool == true)
        #expect(out["attempts"] as? Int == 2)
        #expect(out["queuedAt"] as? String == "1970-01-01T00:16:40Z")
        // The photo itself is never in the text.
        #expect(!PendingExport.json([item(.font, newFont: font, photo: "x.jpg")]).contains("x.jpg"))
    }

    @Test func aReviewNamesTheFountainAndItsStatus() throws {
        let review = NewReview(waterStatus: "dry", confirmIfUnchanged: true, remoteDistanceM: nil)
        let out = try #require(decode(PendingExport.json([item(.review, review: review)])).first)
        #expect(out["type"] as? String == "review")
        #expect(out["name"] as? String == "Font del Faig")
        #expect(out["fontID"] as? String == fontID.uuidString)
        #expect(out["waterStatus"] as? String == "dry")
        #expect(out["hasPhoto"] as? Bool == false)
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
