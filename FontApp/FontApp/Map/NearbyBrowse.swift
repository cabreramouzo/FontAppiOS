import CoreLocation
import Foundation

/// Going from fountain to fountain from its sheet, as the map lies: an imaginary vertical
/// line through the current one; swiping left brings the nearest fountain on its right
/// (the map slides left, as a page would), swiping right the nearest on its left. After
/// each step the line moves to the new fountain.
nonisolated enum NearbyBrowse {
    enum Side: Equatable { case east, west }

    /// The nearest fountain on that side of the line through `current`. One exactly on
    /// the line belongs to neither side.
    static func neighbour(of current: FontSummary, on side: Side, among fonts: [FontSummary]) -> FontSummary? {
        let here = CLLocation(latitude: current.latitude, longitude: current.longitude)
        return fonts
            .filter { $0.id != current.id && (side == .east ? $0.longitude > current.longitude : $0.longitude < current.longitude) }
            .min { here.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))
                < here.distance(from: CLLocation(latitude: $1.latitude, longitude: $1.longitude)) }
    }

    /// A swipe on the short card: horizontal, clear and long enough. Anything more
    /// vertical belongs to the sheet (up and down). Left brings what is on the right.
    static func swipe(dx: Double, dy: Double) -> Side? {
        guard abs(dx) >= 60, abs(dx) > abs(dy) * 2 else { return nil }
        return dx < 0 ? .east : .west
    }
}
