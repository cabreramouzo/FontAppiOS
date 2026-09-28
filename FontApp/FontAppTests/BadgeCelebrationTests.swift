import Foundation
import Testing
@testable import FontApp

/// When the app says "you just earned it": never the first time, the level before a
/// badge, and the highest tier when several arrive together.
@MainActor struct BadgeCelebrationTests {
    private let me = UUID()

    private func defaults() -> UserDefaults { UserDefaults(suiteName: "badges-\(UUID().uuidString)")! }

    private func preview(_ badges: [(String, String)], level: String) -> BadgesPreview {
        BadgesPreview(badges: badges.map { .init(family: $0.0, tier: $0.1) }, level: level)
    }

    @Test func theFirstLookOnlyRemembers() {
        let store = defaults()
        let first = BadgeCelebrations.novelty(in: preview([("pioneer", "unique")], level: "drop"), user: me, defaults: store)
        #expect(first == nil)
        let again = BadgeCelebrations.novelty(in: preview([("pioneer", "unique")], level: "drop"), user: me, defaults: store)
        #expect(again == nil)
    }

    @Test func aNewBadgeIsCelebratedOnce() {
        let store = defaults()
        _ = BadgeCelebrations.novelty(in: preview([], level: "drop"), user: me, defaults: store)
        let novelty = BadgeCelebrations.novelty(in: preview([("pioneer", "unique")], level: "drop"), user: me, defaults: store)
        #expect(novelty?.badge?.family == "pioneer")
        #expect(BadgeCelebrations.novelty(in: preview([("pioneer", "unique")], level: "drop"), user: me, defaults: store) == nil)
    }

    @Test func goingUpFromBronzeToSilverCounts() {
        let store = defaults()
        _ = BadgeCelebrations.novelty(in: preview([("routes", "bronze")], level: "drop"), user: me, defaults: store)
        let novelty = BadgeCelebrations.novelty(in: preview([("routes", "silver")], level: "drop"), user: me, defaults: store)
        #expect(novelty?.badge?.tier == "silver")
    }

    @Test func aLevelGoesFirstAndCountsTheBadges() {
        let store = defaults()
        _ = BadgeCelebrations.novelty(in: preview([], level: "drop"), user: me, defaults: store)
        let novelty = BadgeCelebrations.novelty(in: preview([("routes", "bronze")], level: "spring"), user: me, defaults: store)
        #expect(novelty?.level == "spring")
        #expect(novelty?.others == 1)
    }

    @Test func theHighestTierIsShownAndTheRestCounted() {
        let store = defaults()
        _ = BadgeCelebrations.novelty(in: preview([], level: "drop"), user: me, defaults: store)
        let novelty = BadgeCelebrations.novelty(in: preview([("routes", "bronze"), ("regions", "gold")], level: "drop"),
                                                user: me, defaults: store)
        #expect(novelty?.badge?.family == "regions")
        #expect(novelty?.others == 1)
    }

    @Test func eachAccountHasItsOwnMemory() {
        let store = defaults()
        _ = BadgeCelebrations.novelty(in: preview([], level: "drop"), user: me, defaults: store)
        // Someone else signing in on this phone: their first look, nothing celebrated.
        #expect(BadgeCelebrations.novelty(in: preview([("pioneer", "unique")], level: "drop"), user: UUID(), defaults: store) == nil)
    }
}
