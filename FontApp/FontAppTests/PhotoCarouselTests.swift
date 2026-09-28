import Foundation
import Testing
@testable import FontApp

/// `web/src/lib/fountainPhotos.ts`, as the carousel orders and picks.
struct PhotoCarouselTests {
    private func review(_ days: Double, image: String?) -> CommentResponse {
        CommentResponse(id: UUID(), userID: nil, username: "a", body: "", rating: nil, waterStatus: "flowing",
                        image: image, createdAt: Date.now.addingTimeInterval(-days * 86_400),
                        confirmations: nil, lastConfirmedAt: nil, confirmedByMe: nil, confirmedInstead: nil)
    }

    @Test func coverFirstThenReviewsNewestFirst() {
        let old = review(10, image: "/uploads/old.jpg"), new = review(1, image: "/uploads/new.jpg")
        let photos = FountainPhoto.all(cover: "/uploads/cover.jpg", reviews: [old, review(0, image: nil), new])
        #expect(photos.map(\.image) == ["/uploads/cover.jpg", "/uploads/new.jpg", "/uploads/old.jpg"])
    }

    @Test func aNewerReviewWithoutPhotoHidesTheLatestButton() {
        #expect(FountainPhoto.latestReviewPhoto([review(5, image: "/x.jpg"), review(1, image: nil)]) == nil)
        let fresh = review(1, image: "/x.jpg")
        #expect(FountainPhoto.latestReviewPhoto([review(5, image: "/y.jpg"), fresh]) == fresh.id.uuidString)
        #expect(FountainPhoto.latestReviewPhoto([review(40, image: "/x.jpg")]) == nil)
    }

    @Test func thePhotoIDIsItsFileName() {
        #expect(PhotoExif.id(of: "/uploads/DACC5780-55EB-4847-B390-3249A51D3638.jpg") == "dacc5780-55eb-4847-b390-3249a51d3638")
        #expect(PhotoExif.id(of: "/demo/fountain-2.svg") == nil)
    }
}
