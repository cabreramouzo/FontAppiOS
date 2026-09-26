import Foundation

/// When to reload the map after it stops moving.
///
/// A move by hand is an intention and reloads at once. While the map **follows the user**
/// it moves on its own with every GPS fix, and the web once burned the whole hourly limit
/// (600/h) in 3 s that way. Then it reloads at most once every `followInterval`; the last
/// position is still loaded, just late.
nonisolated struct ReloadThrottle: Sendable {
    static let followInterval: TimeInterval = 6

    private(set) var lastRequest: Date?

    enum Decision: Equatable {
        case now
        case at(Date)
    }

    func decide(following: Bool, now: Date = .now) -> Decision {
        guard following, let last = lastRequest else { return .now }
        let next = last.addingTimeInterval(Self.followInterval)
        return next <= now ? .now : .at(next)
    }

    mutating func didRequest(at date: Date = .now) {
        lastRequest = date
    }
}
