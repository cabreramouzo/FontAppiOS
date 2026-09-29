import Foundation
import Testing
@testable import FontApp

struct NearbyBrowseTests {
    private func font(_ name: String, _ lat: Double, _ long: Double) -> FontSummary {
        FontSummary(id: UUID(), name: name, latitude: lat, longitude: long, image: nil, description: nil, source: nil,
                    drinkable: nil, country: nil, region: nil, createdAt: nil, lastWaterStatus: nil, lastUpdate: nil,
                    latestConfirmations: nil, recentStatusReporters: nil, recentStatusConflict: nil)
    }

    @Test func startsAtTheTappedOneThenByDistanceFromIt() {
        let tapped = font("T", 41.0, 2.0)
        let far = font("far", 41.01, 2.0), near = font("near", 41.001, 2.0), mid = font("mid", 41.005, 2.0)
        let b = NearbyBrowse(anchor: tapped, among: [far, tapped, near, mid])
        #expect(b.fonts.map(\.name) == ["T", "near", "mid", "far"])
        #expect(b.current.name == "T" && !b.hasPrevious && b.hasNext)
    }

    @Test func goingBackAlwaysReturnsToTheSameOne() {
        var b = NearbyBrowse(anchor: font("T", 41, 2), among: [font("a", 41.001, 2), font("b", 41.002, 2)])
        #expect(b.next()?.name == "a")
        #expect(b.next()?.name == "b")
        #expect(b.next() == nil)
        #expect(b.previous()?.name == "a")
        #expect(b.previous()?.name == "T")
        #expect(b.previous() == nil)
    }

    @Test func boundedAndOnlyUsefulWithOthers() {
        let many = (1...50).map { font("\($0)", 41 + Double($0) * 0.001, 2) }
        #expect(NearbyBrowse(anchor: font("T", 41, 2), among: many).fonts.count == NearbyBrowse.limit)
        #expect(!NearbyBrowse(anchor: font("T", 41, 2), among: []).isUseful)
    }

    @Test func onlyAClearHorizontalSwipeBrowses() {
        #expect(NearbyBrowse.swipe(dx: -120, dy: 10) == .next)
        #expect(NearbyBrowse.swipe(dx: 120, dy: -20) == .previous)
        #expect(NearbyBrowse.swipe(dx: -40, dy: 0) == nil)      // too short
        #expect(NearbyBrowse.swipe(dx: -100, dy: -80) == nil)   // mostly vertical: the sheet's
    }
}
