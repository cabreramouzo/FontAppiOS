import Foundation
import Observation

/// What is yours, for the profile: your score, your collection, the fountains that depend
/// on you, the ones you added and your reviews. Loaded together each
/// time the profile opens; a failed load keeps what was there, so without signal the
/// lists do not turn into "you have none yet".
@Observable
final class ProfileModel {
    private(set) var fonts: [FontSummary]?
    private(set) var comments: [MyComment]?
    private(set) var failed: String?
    /// `nil` when switched off, or before the first load: either way nothing is drawn.
    private(set) var game: GamificationSummary?
    private(set) var collection: VisitedCollection?
    private(set) var guarded: [GuardedFont]?

    @ObservationIgnored private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
    }

    /// `near`: a position the app already has permission for, for the local goal.
    func load(near: (latitude: Double, longitude: Double)? = nil) async {
        // The game's parts are extras: one failing does not hide the lists, and a
        // failure keeps what was shown.
        async let game = try? api.gamification()
        async let collection = try? api.visitedCollection(near: near)
        async let guarded = try? api.guardedFonts()
        async let fonts = api.myFonts()
        async let comments = api.myComments()
        let extras = await (game, collection, guarded)
        if let game = extras.0 { self.game = game }
        if let collection = extras.1 { self.collection = collection }
        if let guarded = extras.2 { self.guarded = guarded }
        do {
            (self.fonts, self.comments) = try await (fonts, comments)
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
        comments = nil
        failed = nil
        game = nil
        collection = nil
        guarded = nil
    }
}
