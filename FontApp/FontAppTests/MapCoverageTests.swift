import Testing
@testable import FontApp

struct MapCoverageTests {
    private func box(_ lat: Double, _ long: Double, span: Double = 0.02) -> MapBox {
        MapBox(minLat: lat - span, maxLat: lat + span, minLong: long - span, maxLong: long + span)!
    }

    @Test func regionalLayersKnowWhereTheyHaveData() {
        let barcelona = box(41.387, 2.169), madrid = box(40.417, -3.704), cupertino = box(37.33, -122.03)
        #expect(MapLayer.icgc.covers(barcelona))
        #expect(!MapLayer.icgc.covers(madrid))
        #expect(MapLayer.ignBase.covers(madrid) && MapLayer.pnoa.covers(box(28.12, -15.43)))
        // The simulator's default place: a blank map there is the layer, not a bug.
        #expect(!MapLayer.ignBase.covers(cupertino) && !MapLayer.icgc.covers(cupertino))
        #expect(MapLayer.world.covers(cupertino) && MapLayer.openTopo.covers(cupertino))
    }

    @Test func aViewThatReachesTheEdgeStillCounts() {
        // Zoomed out over Aragon, with Lleida at the edge of the screen.
        #expect(MapLayer.icgc.covers(MapBox(minLat: 41.0, maxLat: 42.0, minLong: -1.5, maxLong: 0.5)!))
    }
}
