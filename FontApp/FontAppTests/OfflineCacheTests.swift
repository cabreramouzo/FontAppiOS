import Foundation
import Testing
@testable import FontApp

struct OfflineCacheTests {
    private func font(_ lat: Double, _ long: Double) -> FontSummary {
        FontSummary(id: UUID(), name: nil, latitude: lat, longitude: long, image: nil, description: nil, source: nil,
                    drinkable: nil, country: nil, region: nil, createdAt: nil, lastWaterStatus: nil, lastUpdate: nil,
                    latestConfirmations: nil, recentStatusReporters: nil, recentStatusConflict: nil)
    }

    @Test func aLoadedAreaIsKnownForAWhileAndInsideIt() {
        let pins = PinCache(file: nil)
        let area = MapBox(minLat: 41, maxLat: 42, minLong: 2, maxLong: 3)!
        let inside = MapBox(minLat: 41.2, maxLat: 41.5, minLong: 2.2, maxLong: 2.5)!
        let now = Date()
        let a = font(41.3, 2.3), b = font(41.9, 2.9)
        pins.store(MapResponse(total: 2, fonts: [a, b], clusters: []), for: area, now: now)
        #expect(pins.isFresh(inside, now: now.addingTimeInterval(60)))
        #expect(!pins.isFresh(inside, now: now.addingTimeInterval(PinCache.freshFor + 1)))
        #expect(!pins.isFresh(MapBox(minLat: 40, maxLat: 41.5, minLong: 2, maxLong: 3)!, now: now))
        #expect(pins.fonts(in: inside).map(\.id) == [a.id])
    }

    @Test func clustersDoNotMakeAnAreaKnownAndGonePinsLeave() {
        let pins = PinCache(file: nil)
        let area = MapBox(minLat: 41, maxLat: 42, minLong: 2, maxLong: 3)!
        let a = font(41.3, 2.3), b = font(41.4, 2.4)
        pins.store(MapResponse(total: 9000, fonts: [a], clusters: [MapCluster(latitude: 41.5, longitude: 2.5, count: 10)]), for: area)
        #expect(!pins.isFresh(area))
        pins.store(MapResponse(total: 2, fonts: [a, b], clusters: []), for: area)
        pins.store(MapResponse(total: 1, fonts: [b], clusters: []), for: area)
        #expect(pins.fonts(in: area).map(\.id) == [b.id])
        pins.invalidate()
        #expect(!pins.isFresh(area))
    }

    @Test func readsAreKeptPerAccount() {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let cache = ResponseCache(directory: dir)
        let url = URL(string: "https://example.com/auth/me")!
        let mine = ResponseCache.key(url: url, bearer: "token-a")
        cache.store(Data("a".utf8), for: mine)
        #expect(cache.data(for: mine) == Data("a".utf8))
        #expect(cache.data(for: ResponseCache.key(url: url, bearer: "token-b")) == nil)
        cache.clear()
        #expect(cache.data(for: mine) == nil)
    }
}
