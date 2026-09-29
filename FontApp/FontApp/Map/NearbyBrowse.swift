import CoreLocation
import Foundation

/// Going from fountain to fountain from its sheet, as a sweep across the map: an
/// imaginary vertical line through the current one moves sideways and stops at the first
/// fountain it meets. Swiping left sweeps right (the map slides left, as a page would),
/// swiping right sweeps left. Only what the screen shows, top to bottom, is met.
nonisolated enum NearbyBrowse {
    enum Side: Equatable { case east, west }

    /// The next fountain the line meets when swept to that side: the smallest step in
    /// longitude, whatever the distance. Only fountains within `latitudes` (what the
    /// screen shows from top to bottom) count: one the eye cannot see is skipped.
    static func neighbour(of current: FontSummary, on side: Side, among fonts: [FontSummary],
                          latitudes: ClosedRange<Double>? = nil) -> FontSummary? {
        let ahead = fonts.filter {
            $0.id != current.id
                && (side == .east ? $0.longitude > current.longitude : $0.longitude < current.longitude)
                && (latitudes?.contains($0.latitude) ?? true)
        }
        return ahead.min { abs($0.longitude - current.longitude) < abs($1.longitude - current.longitude) }
    }

    /// A swipe on the short card: horizontal, clear and long enough. Anything more
    /// vertical belongs to the sheet (up and down). Left brings what is on the right.
    static func swipe(dx: Double, dy: Double) -> Side? {
        guard abs(dx) >= 60, abs(dx) > abs(dy) * 2 else { return nil }
        return dx < 0 ? .east : .west
    }
}
