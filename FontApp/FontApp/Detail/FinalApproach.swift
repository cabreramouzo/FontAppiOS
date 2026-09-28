import CoreLocation
import SwiftUI

/// The last metres: when to guide someone to a fountain, and where to.
/// Port of `web/src/lib/approach.ts` — its comments hold the reasoning (a mountain biker
/// who could not find the fountain inside a park; "you are there" said forty metres away
/// under trees).
nonisolated enum Approach: Equatable {
    /// Guidance starts under this distance. Further away, a straight arrow sends you into a river.
    static let guideMeters: Double = 150
    /// Arriving is a real distance, not the accuracy the phone claims: with a poor
    /// signal you know less, so saying "you are there" must be harder, not easier.
    static let arrivedMeters: Double = 5

    case far
    /// On top of it: no arrow, it would be GPS noise.
    case arrived
    /// Close, but what is left fits inside the GPS margin: pointing would lie. Not arrived.
    case near(meters: Double)
    /// Degrees to turn from where the phone faces: 0 ahead, 90 right. Nil without a compass.
    case guiding(turn: Double?)

    static func guide(meters: Double, accuracy: Double?, heading: Double?, bearing: Double) -> Approach {
        guard meters.isFinite, meters <= guideMeters else { return .far }
        if meters <= arrivedMeters { return .arrived }
        if meters <= (accuracy ?? 0) { return .near(meters: meters) }
        guard let heading else { return .guiding(turn: nil) }
        return .guiding(turn: ((bearing - heading).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360))
    }

    /// Initial great-circle bearing, degrees from north.
    static func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let r = Double.pi / 180
        let dLong = (b.longitude - a.longitude) * r
        let f1 = a.latitude * r, f2 = b.latitude * r
        let y = sin(dLong) * cos(f2)
        let x = cos(f1) * sin(f2) - sin(f1) * cos(f2) * cos(dLong)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }
}

/// Precise position and compass, only while a fountain's page is on screen: the app's
/// shared location is coarse on purpose (battery), and this is the one thing that guides
/// someone on foot, where ±10 or ±40 m is finding it or walking in circles.
@Observable
final class ApproachTracker: NSObject, CLLocationManagerDelegate {
    private(set) var location: CLLocation?
    private(set) var heading: Double?

    @ObservationIgnored private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 1
        manager.headingFilter = 2
    }

    /// Never asks: without permission already given nobody knows you are near, and a
    /// prompt on every page ends in a "deny" that stays.
    func start() {
        let status = manager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { return }
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        Task { @MainActor in self.location = last }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // A negative accuracy means the reading is not valid: no arrow rather than a wrong one.
        let value: Double? = newHeading.headingAccuracy < 0 ? nil
            : (newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading)
        Task { @MainActor in self.heading = value }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {}
}

/// The card: an arrow to the fountain under 150 m, "you are there" within 5 m, and the
/// honest middle where the GPS can no longer point and the photo does the work.
struct FinalApproachSection: View {
    let coordinate: CLLocationCoordinate2D
    let hasPhoto: Bool
    /// Started and stopped by the page: an empty section never appears, so it could not
    /// start itself.
    let tracker: ApproachTracker
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder var body: some View {
            if let here = tracker.location {
                let target = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                let meters = here.distance(from: target)
                let state = Approach.guide(meters: meters,
                                           accuracy: here.horizontalAccuracy >= 0 ? here.horizontalAccuracy : nil,
                                           heading: tracker.heading,
                                           bearing: Approach.bearing(from: here.coordinate, to: coordinate))
                if state != .far { card(state, meters: meters) }
            }
    }

    private func card(_ state: Approach, meters: Double) -> some View {
        let arrived = state == .arrived
        return Section {
            HStack(spacing: 16) {
                switch state {
                case .guiding(let turn?):
                    Image(systemName: "location.north.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 56, height: 56)
                        .background(Color.accentColor.opacity(0.12), in: Circle())
                        .rotationEffect(.degrees(turn))
                        .animation(reduceMotion ? nil : .linear(duration: 0.2), value: turn)
                case .arrived:
                    Image(systemName: "checkmark.circle").font(.system(size: 44)).foregroundStyle(.green)
                        .frame(width: 56, height: 56)
                default:
                    Image(systemName: "mappin.and.ellipse").font(.system(size: 36)).foregroundStyle(Color.accentColor)
                        .frame(width: 56, height: 56)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(arrived ? L10n.t("approach.here") : L10n.t("approach.away", ["m": Int(meters.rounded())]))
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(arrived ? .green : .primary)
                    Text(detail(state)).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 6)
            .accessibilityElement(children: .combine)
            .sensoryFeedback(.success, trigger: arrived) { _, now in now }
        }
        // Green when there, as Find My does: a signal seen with the phone in the hand.
        // Not the only carrier of meaning: the words change too.
        .listRowBackground(arrived ? Color.green.opacity(0.14) : nil)
    }

    private func detail(_ state: Approach) -> String {
        switch state {
        case .arrived: L10n.t(hasPhoto ? "approach.hereWithPhoto" : "approach.hereNoPhoto")
        case .near: L10n.t(hasPhoto ? "approach.nearWithPhoto" : "approach.nearNoPhoto")
        case .guiding(nil): L10n.t("approach.noCompass")
        default: L10n.t("approach.follow")
        }
    }
}
