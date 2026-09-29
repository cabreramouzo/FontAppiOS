import Foundation
import Testing
@testable import FontApp

struct RecentFountainsTests {
    private func defaults() -> UserDefaults {
        let name = "recent-\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }

    private func font(_ name: String) -> FontSummary {
        FontSummary(id: UUID(), name: name, latitude: 41, longitude: 2, image: nil, description: nil, source: nil,
                    drinkable: nil, country: nil, region: nil, createdAt: nil, lastWaterStatus: nil, lastUpdate: nil,
                    latestConfirmations: nil, recentStatusReporters: nil, recentStatusConflict: nil)
    }

    @Test func latestFirstNoRepeatsAndOnlyFive() {
        let d = defaults()
        let fonts = (1...7).map { font("F\($0)") }
        for f in fonts { RecentFountains.add(f, for: nil, d) }
        RecentFountains.add(fonts[3], for: nil, d)   // looked up again: back to the top
        #expect(RecentFountains.list(for: nil, d).map(\.name) == ["F4", "F7", "F6", "F5", "F3"])
    }

    @Test func eachCanBeForgottenAndTheListCleared() {
        let d = defaults()
        let a = font("A"), b = font("B")
        RecentFountains.add(a, for: nil, d)
        RecentFountains.add(b, for: nil, d)
        #expect(RecentFountains.remove(a.id, for: nil, d).map(\.name) == ["B"])
        #expect(RecentFountains.clear(for: nil, d).isEmpty)
    }

    @Test func eachAccountHasItsOwn() {
        let d = defaults()
        let me = UUID()
        RecentFountains.add(font("Mine"), for: me, d)
        #expect(RecentFountains.list(for: UUID(), d).isEmpty)
        #expect(RecentFountains.list(for: nil, d).isEmpty)
        #expect(RecentFountains.list(for: me, d).count == 1)
    }
}
