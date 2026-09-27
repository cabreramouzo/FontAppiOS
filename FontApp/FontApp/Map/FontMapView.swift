import MapKit
import SwiftUI

/// A fountain on the map.
final class FontAnnotation: NSObject, MKAnnotation {
    let font: FontSummary
    let coordinate: CLLocationCoordinate2D

    init(_ font: FontSummary) {
        self.font = font
        coordinate = CLLocationCoordinate2D(latitude: font.latitude, longitude: font.longitude)
    }

    var title: String? { L10n.fontName(font.name) }
}

/// A server-side cluster: too many fountains in view to send them one by one.
final class ServerClusterAnnotation: NSObject, MKAnnotation {
    let cluster: MapCluster
    let coordinate: CLLocationCoordinate2D

    init(_ cluster: MapCluster) {
        self.cluster = cluster
        coordinate = CLLocationCoordinate2D(latitude: cluster.latitude, longitude: cluster.longitude)
    }
}

/// `MKMapView` rather than SwiftUI's `Map`: it handles thousands of annotations with
/// native clustering, and `userTrackingMode` tells exactly when the map is following the
/// user, which is what the reload throttle needs.
struct FontMapView: UIViewRepresentable {
    let fonts: [FontSummary]
    let clusters: [MapCluster]
    let initialRegion: (CGSize) -> MKCoordinateRegion
    let showsUser: Bool
    /// Bumped by the owner to start following the user (e.g. when permission arrives).
    let followRequest: Int
    let onMove: (MKCoordinateRegion, CGSize, Bool) -> Void
    let onSelect: (FontSummary) -> Void
    let controller: MapController
    /// An imported GPX route, drawn over the map.
    var route: [CLLocationCoordinate2D] = []

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = LayoutAwareMapView()
        map.onFirstLayout = { [weak coordinator = context.coordinator] map in coordinator?.mapDidLayout(map) }
        map.delegate = context.coordinator
        // The compass and the tracking button live in the SwiftUI control column.
        map.showsCompass = false
        map.pointOfInterestFilter = .excludingAll
        map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: Coordinator.fontID)
        map.register(ServerClusterView.self, forAnnotationViewWithReuseIdentifier: Coordinator.serverClusterID)
        map.register(LocalClusterView.self,
                     forAnnotationViewWithReuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier)
        controller.attach(map)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        map.showsUserLocation = showsUser
        coordinator.apply(controller.layer, to: map)
        coordinator.show(route: route, on: map)
        if coordinator.followRequest != followRequest {
            coordinator.followRequest = followRequest
            if showsUser { coordinator.startFollowing(map) }
        }
        coordinator.sync(map, fonts: fonts, clusters: clusters)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        static let fontID = "font"
        static let serverClusterID = "serverCluster"

        var parent: FontMapView
        var followRequest = 0
        private var placedInitialRegion = false
        /// Waiting for the first fix before following.
        private var wantsFollow = false
        private var fontAnnotations: [UUID: FontAnnotation] = [:]
        private var clusterAnnotations: [ServerClusterAnnotation] = []
        /// What the server sent, before joining overlapping circles.
        private var serverClusters: [MapCluster] = []
        private var shownLayer: MapLayer?
        private var tileOverlay: LayerTileOverlay?
        private var routeLine: MKPolyline?
        private var routeCount = 0

        init(_ parent: FontMapView) {
            self.parent = parent
        }

        /// Swaps the base map. Raster layers replace Apple's map entirely
        /// (`canReplaceMapContent`), and go under the pins.
        func apply(_ layer: MapLayer, to map: MKMapView) {
            guard layer != shownLayer else { return }
            shownLayer = layer
            if let tileOverlay { map.removeOverlay(tileOverlay) }
            tileOverlay = nil
            switch layer {
            case .apple:
                let config = MKStandardMapConfiguration(elevationStyle: .realistic)
                // Shops and schools compete with the pins; the map is about water.
                config.pointOfInterestFilter = .excludingAll
                map.preferredConfiguration = config
            case .appleSatellite:
                let config = MKHybridMapConfiguration(elevationStyle: .realistic)
                config.pointOfInterestFilter = .excludingAll
                map.preferredConfiguration = config
            default:
                let overlay = LayerTileOverlay(layer: layer)
                tileOverlay = overlay
                map.addOverlay(overlay, level: .aboveLabels)
            }
            // The route goes on top of whatever base map was just added.
            if let routeLine {
                map.removeOverlay(routeLine)
                map.addOverlay(routeLine, level: .aboveLabels)
            }
        }

        func show(route: [CLLocationCoordinate2D], on map: MKMapView) {
            guard route.count != routeCount else { return }
            routeCount = route.count
            if let routeLine { map.removeOverlay(routeLine) }
            routeLine = nil
            guard route.count >= 2 else { return }
            let line = MKPolyline(coordinates: route, count: route.count)
            routeLine = line
            map.addOverlay(line, level: .aboveLabels)
            map.setVisibleMapRect(line.boundingMapRect,
                                  edgePadding: UIEdgeInsets(top: 110, left: 30, bottom: map.bounds.height * 0.5, right: 70), animated: true)
        }

        func mapView(_ map: MKMapView, didChange mode: MKUserTrackingMode, animated: Bool) {
            parent.controller.trackingMode = mode
        }

        func mapView(_ map: MKMapView, rendererFor overlay: any MKOverlay) -> MKOverlayRenderer {
            if let tiles = overlay as? MKTileOverlay { return MKTileOverlayRenderer(tileOverlay: tiles) }
            if let line = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: line)
                renderer.strokeColor = UIColor(Color(hex: 0xE11D48))
                renderer.lineWidth = 5
                renderer.lineCap = .round
                renderer.lineJoin = .round
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        /// Adds and removes only what changed: rebuilding thousands of annotations on
        /// every reload would flicker and drop the selection.
        func sync(_ map: MKMapView, fonts: [FontSummary], clusters: [MapCluster]) {
            var incoming: [UUID: FontSummary] = [:]
            for font in fonts { incoming[font.id] = font }
            var toRemove: [MKAnnotation] = []
            var toAdd: [MKAnnotation] = []
            for (id, annotation) in fontAnnotations where incoming[id] != annotation.font {
                toRemove.append(annotation)
                fontAnnotations[id] = nil
            }
            for (id, font) in incoming where fontAnnotations[id] == nil {
                let annotation = FontAnnotation(font)
                fontAnnotations[id] = annotation
                toAdd.append(annotation)
            }
            if serverClusters != clusters {
                serverClusters = clusters
                toRemove += clusterAnnotations
                let merged = ClusterMerge.merge(clusters) { cluster in
                    map.convert(CLLocationCoordinate2D(latitude: cluster.latitude, longitude: cluster.longitude),
                                toPointTo: map)
                }
                clusterAnnotations = merged.map(ServerClusterAnnotation.init)
                toAdd += clusterAnnotations
            }
            if !toRemove.isEmpty { map.removeAnnotations(toRemove) }
            if !toAdd.isEmpty { map.addAnnotations(toAdd) }
        }

        /// The first moment the map has a size: place the starting view (unless it is
        /// already following the user) and ask for its fountains.
        func mapDidLayout(_ map: MKMapView) {
            placedInitialRegion = true
            if map.userTrackingMode == .none, !wantsFollow {
                map.setRegion(parent.initialRegion(map.bounds.size), animated: false)
            }
            parent.onMove(map.region, map.bounds.size, map.userTrackingMode != .none)
        }

        /// Follows the user at neighbourhood scale. `.follow` on its own jumps to street
        /// level, where the nearest fountain is usually off screen.
        func startFollowing(_ map: MKMapView) {
            guard let location = map.userLocation.location else {
                wantsFollow = true
                return
            }
            wantsFollow = false
            let region = MKCoordinateRegion(center: location.coordinate,
                                            latitudinalMeters: 1500, longitudinalMeters: 1500)
            map.setRegion(region, animated: false)
            map.setUserTrackingMode(.follow, animated: false)
        }

        func mapView(_ map: MKMapView, didUpdate userLocation: MKUserLocation) {
            if wantsFollow { startFollowing(map) }
        }

        func mapView(_ map: MKMapView, regionDidChangeAnimated animated: Bool) {
            guard placedInitialRegion else { return }
            parent.onMove(map.region, map.bounds.size, map.userTrackingMode != .none)
        }

        func mapView(_ map: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            switch annotation {
            case let font as FontAnnotation:
                let view = map.dequeueReusableAnnotationView(withIdentifier: Self.fontID, for: font)
                    as! MKMarkerAnnotationView
                view.markerTintColor = UIColor(WaterStatus.color(for: font.font.lastWaterStatus))
                view.glyphImage = UIImage(systemName: "drop.fill")
                view.clusteringIdentifier = "font"
                view.titleVisibility = .hidden
                view.canShowCallout = false
                return view
            case let cluster as ServerClusterAnnotation:
                let view = map.dequeueReusableAnnotationView(withIdentifier: Self.serverClusterID, for: cluster)
                (view as? ServerClusterView)?.configure(count: cluster.cluster.count)
                return view
            default:
                return nil // user location and MapKit's own clusters use their defaults
            }
        }

        func mapView(_ map: MKMapView, didSelect annotation: MKAnnotation) {
            map.deselectAnnotation(annotation, animated: false)
            switch annotation {
            case let font as FontAnnotation:
                parent.onSelect(font.font)
            case let cluster as ServerClusterAnnotation:
                zoom(map, into: cluster.coordinate, factor: 4)
            case let local as MKClusterAnnotation:
                show(local.memberAnnotations, in: map)
            default:
                break
            }
        }

        /// Zooms to a group of pins, but never closer than a few streets: two fountains a
        /// few metres apart used to land the map at building level, with nothing around
        /// to tell where it was.
        private func show(_ annotations: [MKAnnotation], in map: MKMapView) {
            var rect = annotations.reduce(MKMapRect.null) { rect, annotation in
                rect.union(MKMapRect(origin: MKMapPoint(annotation.coordinate), size: MKMapSize(width: 0, height: 0)))
            }
            guard !rect.isNull else { return }
            let minSide = MKMapPointsPerMeterAtLatitude(rect.origin.coordinate.latitude) * Self.minZoomMeters
            if rect.size.width < minSide && rect.size.height < minSide {
                rect = rect.insetBy(dx: (rect.size.width - minSide) / 2, dy: (rect.size.height - minSide) / 2)
            }
            map.setVisibleMapRect(rect, edgePadding: UIEdgeInsets(top: 60, left: 40, bottom: 60, right: 40),
                                  animated: true)
        }

        /// The closest a tap on a group zooms: about this many metres across.
        static let minZoomMeters: Double = 500

        private func zoom(_ map: MKMapView, into center: CLLocationCoordinate2D, factor: Double) {
            let span = MKCoordinateSpan(latitudeDelta: map.region.span.latitudeDelta / factor,
                                        longitudeDelta: map.region.span.longitudeDelta / factor)
            map.setRegion(MKCoordinateRegion(center: center, span: span), animated: true)
        }
    }
}

/// Reports the first layout with a real size, which SwiftUI's update pass does not
/// guarantee to have happened yet.
final class LayoutAwareMapView: MKMapView {
    var onFirstLayout: ((MKMapView) -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0, let callback = onFirstLayout else { return }
        onFirstLayout = nil
        callback(self)
    }
}

/// MapKit's own grouping of overlapping pins, drawn like the server clusters.
final class LocalClusterView: MKAnnotationView {
    private let bubble = ClusterBubble()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        bubble.install(in: self)
        displayPriority = .required
        collisionMode = .circle
    }

    required init?(coder: NSCoder) { fatalError() }

    override func prepareForDisplay() {
        super.prepareForDisplay()
        let count = (annotation as? MKClusterAnnotation)?.memberAnnotations.count ?? 0
        bubble.set(count: count, view: self)
    }
}

/// A server cluster: a circle with the number of fountains in it.
final class ServerClusterView: MKAnnotationView {
    private let bubble = ClusterBubble()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        bubble.install(in: self)
        displayPriority = .required
        collisionMode = .circle
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(count: Int) {
        bubble.set(count: count, view: self)
    }
}

/// Shared drawing for both cluster kinds. The circle grows with the count, never below
/// the 44 pt touch target.
private struct ClusterBubble {
    let label = UILabel()

    func install(in view: MKAnnotationView) {
        label.textAlignment = .center
        label.textColor = .white
        label.font = .systemFont(ofSize: 15, weight: .bold)
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.6
        label.layer.masksToBounds = true
        label.layer.borderColor = UIColor.white.cgColor
        label.layer.borderWidth = 2
        label.backgroundColor = UIColor(WaterStatus.noStatusColor)
        view.addSubview(label)
    }

    func set(count: Int, view: MKAnnotationView) {
        let side: CGFloat = count >= 1000 ? 52 : count >= 100 ? 48 : 44
        view.frame.size = CGSize(width: side, height: side)
        label.frame = CGRect(x: 0, y: 0, width: side, height: side)
        label.layer.cornerRadius = side / 2
        label.text = count.formatted(.number.notation(.compactName))
        view.accessibilityLabel = L10n.t("map.clusterCount", ["n": count])
        view.isAccessibilityElement = true
    }
}
