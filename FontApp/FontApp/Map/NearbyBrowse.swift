import CoreLocation
import Foundation

/// Going through the fountains around the one first tapped, from its sheet: swipe left
/// for the next nearest, right to go back. An ordered list and not "whichever lies on
/// that side of the map": a fountain straight above has no side, and going back must
/// always return to the same one.
nonisolated struct NearbyBrowse: Equatable, Sendable {
    /// Enough for a walk around; a list of hundreds is not browsed by swiping.
    static let limit = 20

    let fonts: [FontSummary]
    private(set) var index: Int

    /// The tapped fountain first, then the others on the map by distance from it.
    init(anchor: FontSummary, among visible: [FontSummary]) {
        let here = CLLocation(latitude: anchor.latitude, longitude: anchor.longitude)
        let others = visible.filter { $0.id != anchor.id }
            .map { ($0, here.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))) }
            .sorted { $0.1 < $1.1 }
            .prefix(Self.limit - 1)
            .map(\.0)
        fonts = [anchor] + others
        index = 0
    }

    var current: FontSummary { fonts[index] }
    var hasNext: Bool { index + 1 < fonts.count }
    var hasPrevious: Bool { index > 0 }
    /// Worth showing only when there is somewhere to go.
    var isUseful: Bool { fonts.count > 1 }

    func contains(_ id: UUID) -> Bool { fonts.contains { $0.id == id } }

    @discardableResult
    mutating func next() -> FontSummary? {
        guard hasNext else { return nil }
        index += 1
        return current
    }

    @discardableResult
    mutating func previous() -> FontSummary? {
        guard hasPrevious else { return nil }
        index -= 1
        return current
    }

    /// A swipe on the short card: horizontal, clear and long enough. Anything more
    /// vertical belongs to the sheet (up and down).
    enum Swipe { case next, previous }
    static func swipe(dx: Double, dy: Double) -> Swipe? {
        guard abs(dx) >= 60, abs(dx) > abs(dy) * 2 else { return nil }
        return dx < 0 ? .next : .previous
    }
}
