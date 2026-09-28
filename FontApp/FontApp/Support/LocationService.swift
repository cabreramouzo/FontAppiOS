import CoreLocation
import Observation

/// When-in-use location for the map and the "near me" feed.
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    private(set) var authorization: CLAuthorizationStatus
    private(set) var location: CLLocation?

    @ObservationIgnored private let manager = CLLocationManager()

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
