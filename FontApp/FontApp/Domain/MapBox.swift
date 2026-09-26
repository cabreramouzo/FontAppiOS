import Foundation
import MapKit

/// The bounding box sent to `/fonts/map`.
///
/// The server rejects anything beyond ±90 / ±180 with a 400, and a zoomed-out MapKit
/// region easily reaches past them (and wraps the antimeridian), so the box is clamped.
nonisolated struct MapBox: Equatable, Sendable {
    let minLat: Double
    let maxLat: Double
    let minLong: Double
    let maxLong: Double

    /// Clamps a visible region. `nil` when nothing valid is left to ask for.
    init?(region: MKCoordinateRegion) {
        let c = region.center
        let halfLat = region.span.latitudeDelta / 2
        let halfLong = region.span.longitudeDelta / 2
        var minLong = c.longitude - halfLong
        var maxLong = c.longitude + halfLong
        // A view that straddles the antimeridian (or spans the whole world) would need two
        // boxes; asking for all longitudes is simpler and still correct.
        if minLong < -180 || maxLong > 180 || halfLong >= 180 {
            minLong = -180
            maxLong = 180
        }
        self.init(minLat: c.latitude - halfLat, maxLat: c.latitude + halfLat,
                  minLong: minLong, maxLong: maxLong)
    }

    init?(minLat: Double, maxLat: Double, minLong: Double, maxLong: Double) {
        let values = [minLat, maxLat, minLong, maxLong]
        guard values.allSatisfy(\.isFinite) else { return nil }
        self.minLat = min(max(minLat, -90), 90)
        self.maxLat = min(max(maxLat, -90), 90)
        self.minLong = min(max(minLong, -180), 180)
        self.maxLong = min(max(maxLong, -180), 180)
        // The server also rejects empty or inverted boxes.
        guard self.minLat < self.maxLat, self.minLong < self.maxLong else { return nil }
    }

    var queryItems: [URLQueryItem] {
        [
            URLQueryItem(name: "minLat", value: String(minLat)),
            URLQueryItem(name: "maxLat", value: String(maxLat)),
            URLQueryItem(name: "minLong", value: String(minLong)),
            URLQueryItem(name: "maxLong", value: String(maxLong)),
        ]
    }
}
