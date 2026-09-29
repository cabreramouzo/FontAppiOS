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

    @Test func theSweepStopsAtTheFirstFountainItMeets() {
        let here = font("here", 41.0, 2.0)
        // Closer as the crow flies but farther sideways: the sweep meets `sideways` first.
        let straightRight = font("straightRight", 41.0, 2.004)
        let sideways = font("sideways", 41.003, 2.001)
        let left = font("left", 41.0, 1.998)
        let all = [here, straightRight, sideways, left]
        #expect(NearbyBrowse.neighbour(of: here, on: .east, among: all)?.name == "sideways")
        #expect(NearbyBrowse.neighbour(of: here, on: .west, among: all)?.name == "left")
    }

    @Test func whatTheScreenDoesNotShowIsSkipped() {
        let here = font("here", 41.0, 2.0)
        let offScreen = font("offScreen", 41.05, 2.001)
        let onScreen = font("onScreen", 41.001, 2.003)
        let band = 40.99...41.01
        #expect(NearbyBrowse.neighbour(of: here, on: .east, among: [here, offScreen, onScreen], latitudes: band)?.name == "onScreen")
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
