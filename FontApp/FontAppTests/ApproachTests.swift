import CoreLocation
import Testing
@testable import FontApp

/// The cases `web/src/lib/approach.test.ts` pins down.
struct ApproachTests {
    @Test func farAwayShowsNothing() {
        #expect(Approach.guide(meters: 151, accuracy: 5, heading: 0, bearing: 0) == .far)
        #expect(Approach.guide(meters: .infinity, accuracy: nil, heading: nil, bearing: 0) == .far)
    }

    @Test func arrivingIsARealDistanceNotTheAccuracy() {
        #expect(Approach.guide(meters: 4, accuracy: 40, heading: 0, bearing: 0) == .arrived)
        // Under trees, ±40 m and forty metres away: close, not there.
        #expect(Approach.guide(meters: 38, accuracy: 40, heading: 0, bearing: 0) == .near(meters: 38))
    }

    @Test func pointsFromWhereThePhoneFaces() {
        #expect(Approach.guide(meters: 80, accuracy: 10, heading: 90, bearing: 180) == .guiding(turn: 90))
        #expect(Approach.guide(meters: 80, accuracy: 10, heading: 350, bearing: 10) == .guiding(turn: 20))
        #expect(Approach.guide(meters: 80, accuracy: 10, heading: nil, bearing: 10) == .guiding(turn: nil))
    }

    @Test func bearingIsFromNorth() {
        let a = CLLocationCoordinate2D(latitude: 41.8, longitude: 2.1)
        #expect(abs(Approach.bearing(from: a, to: .init(latitude: 41.81, longitude: 2.1))) < 0.01)
        #expect(abs(Approach.bearing(from: a, to: .init(latitude: 41.8, longitude: 2.11)) - 90) < 0.1)
    }
}
