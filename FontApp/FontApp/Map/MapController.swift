import MapKit
import MapLibre
import Observation

/// Lets the SwiftUI controls act on the map (zoom to a result, read the visible box,
/// follow the user) without the view owning them.
@Observable
final class MapController {
    @ObservationIgnored weak var mapView: MLNMapView?

    /// The layer on screen. Remembered between launches.
    var layer: MapLayer = MapLayer.saved {
        didSet {
            UserDefaults.standard.set(layer.rawValue, forKey: MapLayer.storageKey)
            checkCoverage()
        }
    }

    /// The view is entirely outside the layer's data: without a word the map just looks
    /// broken (blank, and no fountains if there are none there either).
    private(set) var outsideCoverage = false

    /// After every move and every change of layer.
    func checkCoverage() {
        guard let box = visibleBox else { return }
        let outside = !layer.covers(box)
        if outside != outsideCoverage { outsideCoverage = outside }
    }

    /// Mirrors the map's tracking mode, for the location button's icon.
    var trackingMode: MLNUserTrackingMode = .none

    func attach(_ map: MLNMapView) {
        mapView = map
    }

    /// The location button: not following → follow → follow with heading → not following.
    func cycleTracking() {
        guard let map = mapView else { return }
        let next: MLNUserTrackingMode = switch map.userTrackingMode {
        case .none: .follow
        case .follow: .followWithHeading
        default: .none
        }
        map.setUserTrackingMode(next, animated: true, completionHandler: nil)
    }

    var visibleBox: MapBox? {
        guard let map = mapView else { return nil }
        return MapBox(bounds: map.visibleCoordinateBounds)
    }

    /// MapLibre's zoom: the web's (256 px tiles) minus one, since its tiles are 512 px.
    var zoom: Double { mapView?.zoomLevel ?? 0 }

    /// Centres a point. `aboveSheet`: a half-height sheet is about to cover the bottom, so
    /// the point goes in the middle of what stays visible.
    func show(_ coordinate: CLLocationCoordinate2D, meters: Double = 600, aboveSheet: Bool = false) {
        let region = MKCoordinateRegion(center: coordinate, latitudinalMeters: meters, longitudinalMeters: meters)
        show(MLNCoordinateBounds(region), aboveSheet: aboveSheet)
    }

    func show(_ rect: MKMapRect, aboveSheet: Bool = false) {
        guard !rect.isNull else { return }
        show(MLNCoordinateBounds(MKCoordinateRegion(rect)), aboveSheet: aboveSheet)
    }

    /// Keeps the zoom and slides the map so the point sits in the middle of what stays
    /// visible above a sheet `covered` points tall, as Apple Maps does with a place. It
    /// moves always, not only when hidden: the sheet is the same, so the pin lands in the
    /// same place every time.
    func reveal(_ coordinate: CLLocationCoordinate2D, covered: CGFloat) {
        guard let map = mapView else { return }
        map.setUserTrackingMode(.none, animated: false, completionHandler: nil)
        let top = map.safeAreaInsets.top
        let visibleMiddle = CGPoint(x: map.bounds.midX, y: (top + map.bounds.height - covered) / 2)
        let pin = map.convert(coordinate, toPointTo: map)
        // Already in view above the card: the map stays still, as Apple Maps does. Moving
        // it anyway made every tap feel like a jump.
        let pinHeight: CGFloat = 60
        let clear = CGRect(x: 24, y: top + pinHeight + 16, width: map.bounds.width - 48,
                           height: map.bounds.height - covered - top - pinHeight - 40)
        if clear.contains(pin) { return }
        let centre = CGPoint(x: map.bounds.midX + pin.x - visibleMiddle.x,
                             y: map.bounds.midY + pin.y - visibleMiddle.y)
        map.setCenter(map.convert(centre, toCoordinateFrom: map), animated: true)
    }

    func show(_ bounds: MLNCoordinateBounds, aboveSheet: Bool = false) {
        guard let map = mapView else { return }
        map.setUserTrackingMode(.none, animated: false, completionHandler: nil)
        let bottom = aboveSheet ? map.bounds.height * 0.5 : 120
        map.setVisibleCoordinateBounds(bounds, edgePadding: UIEdgeInsets(top: 80, left: 30, bottom: bottom, right: 70),
                                       animated: true, completionHandler: nil)
    }
}

extension MLNCoordinateBounds {
    nonisolated init(_ region: MKCoordinateRegion) {
        self.init(sw: CLLocationCoordinate2D(latitude: region.center.latitude - region.span.latitudeDelta / 2,
                                             longitude: region.center.longitude - region.span.longitudeDelta / 2),
                  ne: CLLocationCoordinate2D(latitude: region.center.latitude + region.span.latitudeDelta / 2,
                                             longitude: region.center.longitude + region.span.longitudeDelta / 2))
    }
}

extension MapBox {
    nonisolated init?(bounds: MLNCoordinateBounds) {
        self.init(minLat: bounds.sw.latitude, maxLat: bounds.ne.latitude,
                  minLong: bounds.sw.longitude, maxLong: bounds.ne.longitude)
    }
}

extension MKCoordinateRegion {
    /// The region a map shows, for code that speaks MapKit (the reload throttle, MapBox).
    nonisolated init(_ bounds: MLNCoordinateBounds) {
        self.init(center: CLLocationCoordinate2D(latitude: (bounds.sw.latitude + bounds.ne.latitude) / 2,
                                                 longitude: (bounds.sw.longitude + bounds.ne.longitude) / 2),
                  span: MKCoordinateSpan(latitudeDelta: bounds.ne.latitude - bounds.sw.latitude,
                                         longitudeDelta: bounds.ne.longitude - bounds.sw.longitude))
    }
}
