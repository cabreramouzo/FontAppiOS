import Foundation
import Testing
@testable import FontApp

/// An imaginary vertical line through the open fountain: swipe left for the nearest on
/// its right, right for the nearest on its left.
struct NearbyBrowseTests {
    private func font(_ name: String, _ lat: Double, _ long: Double) -> FontSummary {
        FontSummary(id: UUID(), name: name, latitude: lat, longitude: long, image: nil, description: nil, source: nil,
                    drinkable: nil, country: nil, region: nil, createdAt: nil, lastWaterStatus: nil, lastUpdate: nil,
                    latestConfirmations: nil, recentStatusReporters: nil, recentStatusConflict: nil)
    }

    @Test func eachSideGetsTheNearestOnThatSideOnly() {
        let here = font("here", 41.0, 2.0)
        // The nearest overall is on the left; the right one is farther but still the answer.
        let leftNear = font("leftNear", 41.0, 1.999)
        let rightFar = font("rightFar", 41.0, 2.005)
        let rightFarther = font("rightFarther", 41.0, 2.01)
        let all = [here, leftNear, rightFar, rightFarther]
        #expect(NearbyBrowse.neighbour(of: here, on: .east, among: all)?.name == "rightFar")
        #expect(NearbyBrowse.neighbour(of: here, on: .west, among: all)?.name == "leftNear")
    }

    @Test func theLineMovesWithEachStep() {
        let a = font("a", 41, 2.000), b = font("b", 41, 2.001), c = font("c", 41, 2.002)
        let all = [a, b, c]
        let second = NearbyBrowse.neighbour(of: a, on: .east, among: all)!
        #expect(second.name == "b")
        #expect(NearbyBrowse.neighbour(of: second, on: .east, among: all)?.name == "c")
        #expect(NearbyBrowse.neighbour(of: second, on: .west, among: all)?.name == "a")
    }

    @Test func nothingOnASideMeansNoStep() {
        let a = font("a", 41, 2.0), above = font("above", 41.01, 2.0)
        // Straight above lies on the line: neither side.
        #expect(NearbyBrowse.neighbour(of: a, on: .east, among: [a, above]) == nil)
        #expect(NearbyBrowse.neighbour(of: a, on: .west, among: [a, above]) == nil)
    }

    @Test func swipingLeftBringsWhatIsOnTheRight() {
        #expect(NearbyBrowse.swipe(dx: -120, dy: 10) == .east)
        #expect(NearbyBrowse.swipe(dx: 120, dy: -20) == .west)
        #expect(NearbyBrowse.swipe(dx: -40, dy: 0) == nil)
        #expect(NearbyBrowse.swipe(dx: -100, dy: -80) == nil)
    }
}
