import CoreLocation
import Observation

/// When-in-use location for the map and the "near me" feed.
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    private(set) var authorization: CLAuthorizationStatus
    private(set) var location: CLLocation?

    @ObservationIgnored private let manager = CLLocationManager()
    /// Screens that need the exact spot right now (placing a new fountain). The map and
    /// the feed make do with 100 m, which spares the battery; a pin does not.
    @ObservationIgnored private var preciseUsers = 0

    var isAuthorized: Bool {
        authorization == .authorizedWhenInUse || authorization == .authorizedAlways
    }

    override init() {
        // Not read here: `authorizationStatus` waits for the system's location service,
        // and at launch that froze the app on a blank screen whenever the service was
        // slow. CoreLocation reports it right after the delegate is set, below.
        authorization = .notDetermined
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 50
    }

    /// Asks once; after a refusal iOS does not show the prompt again.
    func requestIfNeeded() {
        if authorization == .notDetermined { manager.requestWhenInUseAuthorization() }
        if isAuthorized { manager.startUpdatingLocation() }
    }

    /// Best accuracy, every fix, until the matching `endPrecise()`.
    func beginPrecise() {
        preciseUsers += 1
        guard preciseUsers == 1 else { return }
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        if isAuthorized { manager.startUpdatingLocation() }
    }

    func endPrecise() {
        guard preciseUsers > 0 else { return }
        preciseUsers -= 1
        guard preciseUsers == 0 else { return }
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 50
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            if self.isAuthorized { self.manager.startUpdatingLocation() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        Task { @MainActor in self.location = last }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {}
}
