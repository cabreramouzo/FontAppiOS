import CoreLocation
import Foundation

/// "Are you reviewing a fountain you are not at?" Port of `web/src/lib/remoteReview.ts`.
///
/// Reviewing from elsewhere is often honest (after a ride, with a GPS that under trees
/// claims hundreds of metres), so this never blocks and never accuses: when the position
/// says the person is clearly far, the app asks once per fountain and the review carries
/// the approximate distance for moderators. Only with location permission already granted:
/// asking for it here would turn a review into a permission prompt.
nonisolated enum RemoteReview {
    /// Further than this, after subtracting the fix's accuracy, counts as "not there".
    static let remoteMeters: Double = 1000
    /// A fix vaguer than this cannot tell "here" from "far".
    static let maxAccuracy: Double = 1000
    /// How old a fix may be and still say where the person is writing from.
    static let maxFixAge: TimeInterval = 3 * 60

    /// Rounded distance in metres when clearly far, else `nil` ("near", "no position",
    /// "too vague" and "too old" all mean: ask nothing, store nothing).
    static func distance(from fix: CLLocation?, to fountain: CLLocationCoordinate2D,
                         now: Date = .now) -> Int? {
        guard let fix, fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= maxAccuracy,
              now.timeIntervalSince(fix.timestamp) <= maxFixAge else { return nil }
        let meters = fix.distance(from: CLLocation(latitude: fountain.latitude, longitude: fountain.longitude))
        guard meters.isFinite, meters - fix.horizontalAccuracy > remoteMeters else { return nil }
        return rounded(meters)
    }

    /// Only an approximate distance is kept, never coordinates: 100 m steps under 10 km,
    /// whole kilometres above.
    static func rounded(_ meters: Double) -> Int {
        meters < 10_000 ? Int((meters / 100).rounded()) * 100 : Int((meters / 1000).rounded()) * 1000
    }

    /// "1,4" / "12": kilometres as shown in the question, in the reader's locale.
    static func kmLabel(_ meters: Int, locale: Locale = .current) -> String {
        let km = Double(meters) / 1000
        return km.formatted(.number.precision(.fractionLength(0...(km < 10 ? 1 : 0))).locale(locale))
    }
}
