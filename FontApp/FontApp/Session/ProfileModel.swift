import Foundation
import Observation

/// What is yours, for the profile: fountains you added, the ones you starred and your
/// reviews. Loaded together each time the profile opens; a failed load keeps what was
/// there, so without signal the lists do not turn into "you have none yet".
@Observable
final class ProfileModel {
    private(set) var fonts: [FontSummary]?
    private(set) var favorites: [FontSummary]?
    private(set) var comments: [MyComment]?
    private(set) var failed: String?

    @ObservationIgnored private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
    }

    func load() async {
        async let fonts = api.myFonts()
        async let favorites = api.myFavorites()
        async let comments = api.myComments()
        do {
            (self.fonts, self.favorites, self.comments) = try await (fonts, favorites, comments)
            failed = nil
        } catch is CancellationError {
            return
        } catch {
            failed = ErrorText.describe(error)
        }
    }

    /// Another account signed in: the last one's lists must not show under it.
    func clear() {
        fonts = nil
        favorites = nil
        comments = nil
        failed = nil
    }
}
