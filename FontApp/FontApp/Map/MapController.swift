import MapKit
import Observation

/// Lets the SwiftUI controls act on the `MKMapView` (zoom to a result, read the visible
/// box, host the system tracking and compass buttons) without the view owning them.
@Observable
final class MapController {
    @ObservationIgnored weak var mapView: MKMapView?

    /// The layer on screen. Remembered between launches.
    var layer: MapLayer = MapLayer.saved {
        didSet { UserDefaults.standard.set(layer.rawValue, forKey: MapLayer.storageKey) }
    }

    /// Mirrors the map's tracking mode, for the location button's icon.
    var trackingMode: MKUserTrackingMode = .none

    /// The location button: not following → follow → follow with heading → not following.
    func cycleTracking() {
        guard let map = mapView else { return }
        let next: MKUserTrackingMode = switch map.userTrackingMode {
        case .none: .follow
        case .follow: .followWithHeading
        default: .none
        }
        map.setUserTrackingMode(next, animated: true)
    }

    /// Bumped when the map view exists, so views that host system buttons for it rebuild.
    private(set) var generation = 0

    func attach(_ map: MKMapView) {
        mapView = map
        generation += 1
    }

    var visibleBox: MapBox? {
        guard let map = mapView else { return nil }
        return MapBox(region: map.region)
    }

    /// The web's zoom level of what is on screen (256 px tiles).
    var zoom: Double {
        guard let map = mapView, map.bounds.width > 0 else { return 0 }
        let degreesPerPoint = map.region.span.longitudeDelta / Double(map.bounds.width)
        return log2(360 / (degreesPerPoint * 256))
    }

    func show(_ coordinate: CLLocationCoordinate2D, meters: Double = 600) {
        guard let map = mapView else { return }
        map.setUserTrackingMode(.none, animated: false)
        map.setRegion(MKCoordinateRegion(center: coordinate, latitudinalMeters: meters, longitudinalMeters: meters),
                      animated: true)
    }

    func show(_ rect: MKMapRect) {
        guard let map = mapView, !rect.isNull else { return }
        map.setUserTrackingMode(.none, animated: false)
        map.setVisibleMapRect(rect, edgePadding: UIEdgeInsets(top: 80, left: 40, bottom: 120, right: 40), animated: true)
    }
}
