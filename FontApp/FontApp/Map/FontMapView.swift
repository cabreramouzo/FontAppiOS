import MapKit
import MapLibre
import SwiftUI

/// The fountain map, on MapLibre Native (see `docs/vector-tiles.md`): the ICGC and IGN
/// vector styles, and offline packs, which MapKit cannot do.
///
/// Fountains are not annotation views but a GeoJSON source drawn by style layers, which
/// is how MapLibre is meant to be used: thousands of points without thousands of views,
/// and native clustering. Our sources and layers are added on top of whatever base style
/// is loaded, and again every time the style changes.
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

    func makeUIView(context: Context) -> MLNMapView {
        let map = LayoutAwareMapView(frame: .zero, styleURL: controller.layer.styleURL)
        map.onFirstLayout = { [weak coordinator = context.coordinator] map in coordinator?.mapDidLayout(map) }
        map.delegate = context.coordinator
        // MapLibre's logo is optional under its licence; the credits are drawn by
        // MapScreen, one line per source, so the (i) button would repeat them.
        map.logoView.isHidden = true
        map.attributionButton.isHidden = true
        map.compassViewPosition = .bottomLeft
        map.compassViewMargins = CGPoint(x: 12, y: 96)
        map.allowsTilting = false
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        // Let MapLibre's own taps (double tap to zoom) go first.
        for recognizer in map.gestureRecognizers ?? [] where (recognizer as? UITapGestureRecognizer)?.numberOfTapsRequired == 2 {
            tap.require(toFail: recognizer)
        }
        map.addGestureRecognizer(tap)
        context.coordinator.shownLayer = controller.layer
        controller.attach(map)
        return map
    }

    func updateUIView(_ map: MLNMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        map.showsUserLocation = showsUser
        if coordinator.shownLayer != controller.layer {
            coordinator.shownLayer = controller.layer
            map.styleURL = controller.layer.styleURL
        }
        if coordinator.followRequest != followRequest {
            coordinator.followRequest = followRequest
            if showsUser { coordinator.startFollowing(map) }
        }
        coordinator.update(map, fonts: fonts, clusters: clusters, route: route)
    }

    final class Coordinator: NSObject, MLNMapViewDelegate {
        var parent: FontMapView
        var followRequest = 0
        var shownLayer: MapLayer?
        private var placedInitialRegion = false
        /// Waiting for the first fix before following.
        private var wantsFollow = false

        private var fonts: [UUID: FontSummary] = [:]
        private var fontsSignature = 0
        private var serverClusters: [MapCluster] = []
        private var route: [CLLocationCoordinate2D] = []
        /// Our sources in the current style; nil until it has loaded.
        private var fontsSource: MLNShapeSource?
        private var clustersSource: MLNShapeSource?
        private var routeSource: MLNShapeSource?

        init(_ parent: FontMapView) {
            self.parent = parent
        }

        // MARK: Data

        func update(_ map: MLNMapView, fonts list: [FontSummary], clusters: [MapCluster],
                    route newRoute: [CLLocationCoordinate2D]) {
            // Rebuilding the GeoJSON only when what is drawn changed: the parent re-renders
            // with every GPS fix.
            var hasher = Hasher()
            for font in list { hasher.combine(font) }
            let signature = hasher.finalize()
            if signature != fontsSignature {
                fontsSignature = signature
                fonts = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                fontsSource?.shape = Self.fontShape(list)
            }
            if clusters != serverClusters {
                serverClusters = clusters
                clustersSource?.shape = clusterShape(map)
            }
            if newRoute.count != route.count {
                route = newRoute
                routeSource?.shape = routeShape()
                if newRoute.count >= 2 { frameRoute(map) }
            }
        }

        private static func fontShape(_ list: [FontSummary]) -> MLNShapeCollectionFeature {
            MLNShapeCollectionFeature(shapes: list.map { font in
                let point = MLNPointFeature()
                point.coordinate = CLLocationCoordinate2D(latitude: font.latitude, longitude: font.longitude)
                point.attributes = [
                    "id": font.id.uuidString,
                    "color": UIColor(WaterStatus.color(for: font.lastWaterStatus)).hexString,
                ]
                return point
            })
        }

        /// Server clusters, joined when they would overlap on screen (`ClusterMerge`).
        private func clusterShape(_ map: MLNMapView) -> MLNShapeCollectionFeature {
            let merged = ClusterMerge.merge(serverClusters) { cluster in
                map.convert(CLLocationCoordinate2D(latitude: cluster.latitude, longitude: cluster.longitude), toPointTo: map)
            }
            return MLNShapeCollectionFeature(shapes: merged.map { cluster in
                let point = MLNPointFeature()
                point.coordinate = CLLocationCoordinate2D(latitude: cluster.latitude, longitude: cluster.longitude)
                point.attributes = ["count": cluster.count,
                                    "label": cluster.count.formatted(.number.notation(.compactName))]
                return point
            })
        }

        private func routeShape() -> MLNShape? {
            guard route.count >= 2 else { return MLNShapeCollectionFeature(shapes: []) }
            var coordinates = route
            return MLNPolylineFeature(coordinates: &coordinates, count: UInt(coordinates.count))
        }

        private func frameRoute(_ map: MLNMapView) {
            var coordinates = route
            let line = MLNPolyline(coordinates: &coordinates, count: UInt(coordinates.count))
            map.setVisibleCoordinateBounds(line.overlayBounds,
                                           edgePadding: UIEdgeInsets(top: 110, left: 30, bottom: map.bounds.height * 0.5, right: 70),
                                           animated: true, completionHandler: nil)
        }

        // MARK: Style

        /// Every style load (first one and each layer change) gets our sources and layers.
        func mapView(_ map: MLNMapView, didFinishLoading style: MLNStyle) {
            let font = Self.countFont(in: style)

            let routeSource = MLNShapeSource(identifier: "fa-route", shape: routeShape(), options: nil)
            style.addSource(routeSource)
            let routeLine = MLNLineStyleLayer(identifier: "fa-route-line", source: routeSource)
            routeLine.lineColor = NSExpression(forConstantValue: UIColor(Color(hex: 0xE11D48)))
            routeLine.lineWidth = NSExpression(forConstantValue: 5)
            routeLine.lineCap = NSExpression(forConstantValue: "round")
            routeLine.lineJoin = NSExpression(forConstantValue: "round")
            style.addLayer(routeLine)
            self.routeSource = routeSource

            // Fountains, clustered by MapLibre where they overlap (the server clusters only
            // above 3,000 in view).
            let fontsSource = MLNShapeSource(
                identifier: "fa-fonts", shape: Self.fontShape(Array(fonts.values)),
                options: [.clustered: true, .clusterRadius: 38, .maximumZoomLevelForClustering: 15])
            style.addSource(fontsSource)
            self.fontsSource = fontsSource

            let pins = MLNCircleStyleLayer(identifier: "fa-pins", source: fontsSource)
            pins.predicate = NSPredicate(format: "cluster != YES")
            pins.circleRadius = NSExpression(forConstantValue: 11)
            // The status colour travels in each point as "#RRGGBB".
            pins.circleColor = NSExpression(format: "CAST(color, 'UIColor')")
            pins.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
            pins.circleStrokeWidth = NSExpression(forConstantValue: 2.5)
            style.addLayer(pins)

            // Drawn white into a bitmap: MapLibre ignores a symbol image's tint.
            if let symbol = UIImage(systemName: "drop.fill",
                                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .bold)) {
                let drop = UIGraphicsImageRenderer(size: symbol.size).image { _ in
                    symbol.withTintColor(.white, renderingMode: .alwaysOriginal).draw(at: .zero)
                }
                style.setImage(drop, forName: "fa-drop")
                let glyph = MLNSymbolStyleLayer(identifier: "fa-pin-drop", source: fontsSource)
                glyph.predicate = NSPredicate(format: "cluster != YES")
                glyph.iconImageName = NSExpression(forConstantValue: "fa-drop")
                glyph.iconAllowsOverlap = NSExpression(forConstantValue: true)
                glyph.iconIgnoresPlacement = NSExpression(forConstantValue: true)
                style.addLayer(glyph)
            }

            addCircles(to: style, identifier: "fa-local", source: fontsSource,
                       predicate: NSPredicate(format: "cluster == YES"), countKey: "point_count_abbreviated",
                       sizeKey: "point_count", font: font)

            let clustersSource = MLNShapeSource(identifier: "fa-server-clusters", shape: clusterShape(map), options: nil)
            style.addSource(clustersSource)
            self.clustersSource = clustersSource
            addCircles(to: style, identifier: "fa-server", source: clustersSource, predicate: nil,
                       countKey: "label", sizeKey: "count", font: font)
        }

        /// A circle with a number, growing with the count, never below the 44 pt target.
        private func addCircles(to style: MLNStyle, identifier: String, source: MLNSource, predicate: NSPredicate?,
                                countKey: String, sizeKey: String, font: String?) {
            let circle = MLNCircleStyleLayer(identifier: identifier, source: source)
            circle.predicate = predicate
            circle.circleColor = NSExpression(forConstantValue: UIColor(WaterStatus.noStatusColor))
            circle.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
            circle.circleStrokeWidth = NSExpression(forConstantValue: 2)
            circle.circleRadius = NSExpression(
                format: "mgl_step:from:stops:(%K, 20, %@)", sizeKey, [100: 24, 1000: 27])
            style.addLayer(circle)
            guard let font else { return }
            let label = MLNSymbolStyleLayer(identifier: "\(identifier)-count", source: source)
            label.predicate = predicate
            label.text = NSExpression(forKeyPath: countKey)
            label.textFontNames = NSExpression(forConstantValue: [font])
            label.textFontSize = NSExpression(forConstantValue: 14)
            label.textColor = NSExpression(forConstantValue: UIColor.white)
            label.textAllowsOverlap = NSExpression(forConstantValue: true)
            label.textIgnoresPlacement = NSExpression(forConstantValue: true)
            style.addLayer(label)
        }

        /// A bold font the style's glyph server has: each style ships its own set, and
        /// asking for one it lacks draws no text at all.
        private static func countFont(in style: MLNStyle) -> String? {
            let names = style.layers.compactMap { layer -> [String]? in
                guard let symbol = layer as? MLNSymbolStyleLayer,
                      let names = symbol.textFontNames?.constantValue as? [String] else { return nil }
                return names
            }.flatMap { $0 }
            if names.isEmpty { return RasterStyle.countFont }
            return names.first { $0.localizedCaseInsensitiveContains("bold") } ?? names.first
        }

        // MARK: Taps

        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let map = gesture.view as? MLNMapView else { return }
            let point = gesture.location(in: map)
            // A 44 pt target around the finger, as Apple asks, whatever the drawn size.
            let rect = CGRect(x: point.x - 22, y: point.y - 22, width: 44, height: 44)
            let hits = map.visibleFeatures(in: rect, styleLayerIdentifiers: ["fa-pins", "fa-local", "fa-server"])
            let nearest = hits.min { a, b in
                distance(map.convert(a.coordinate, toPointTo: map), point) < distance(map.convert(b.coordinate, toPointTo: map), point)
            }
            guard let hit = nearest else { return }
            if let cluster = hit as? MLNPointFeatureCluster, let source = fontsSource {
                // Into the group, but never closer than a few streets: two fountains metres
                // apart used to land the map at building level.
                let zoom = min(source.zoomLevel(forExpanding: cluster), 16)
                map.setCenter(cluster.coordinate, zoomLevel: max(zoom, map.zoomLevel + 1), animated: true)
            } else if hit.attribute(forKey: "count") != nil {
                map.setCenter(hit.coordinate, zoomLevel: map.zoomLevel + 2, animated: true)
            } else if let raw = hit.attribute(forKey: "id") as? String, let id = UUID(uuidString: raw),
                      let font = fonts[id] {
                parent.onSelect(font)
            }
        }

        private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

        // MARK: Camera

        func mapDidLayout(_ map: MLNMapView) {
            placedInitialRegion = true
            if map.userTrackingMode == .none, !wantsFollow {
                let region = parent.initialRegion(map.bounds.size)
                map.setVisibleCoordinateBounds(MLNCoordinateBounds(region), animated: false)
            }
            parent.onMove(MKCoordinateRegion(map.visibleCoordinateBounds), map.bounds.size, map.userTrackingMode != .none)
        }

        /// Follows the user at neighbourhood scale; `.follow` alone would jump to street level.
        func startFollowing(_ map: MLNMapView) {
            guard let location = map.userLocation?.location else {
                wantsFollow = true
                return
            }
            wantsFollow = false
            map.setCenter(location.coordinate, zoomLevel: 15, animated: false)
            map.setUserTrackingMode(.follow, animated: false, completionHandler: nil)
        }

        func mapView(_ map: MLNMapView, didUpdate userLocation: MLNUserLocation?) {
            if wantsFollow { startFollowing(map) }
        }

        func mapView(_ map: MLNMapView, didChange mode: MLNUserTrackingMode, animated: Bool) {
            parent.controller.trackingMode = mode
        }

        func mapView(_ map: MLNMapView, regionDidChangeAnimated animated: Bool) {
            guard placedInitialRegion else { return }
            // Server clusters are joined by screen distance, which changes with the zoom.
            if !serverClusters.isEmpty { clustersSource?.shape = clusterShape(map) }
            parent.onMove(MKCoordinateRegion(map.visibleCoordinateBounds), map.bounds.size, map.userTrackingMode != .none)
        }
    }
}

/// Reports the first layout with a real size, which SwiftUI's update pass does not
/// guarantee to have happened yet.
final class LayoutAwareMapView: MLNMapView {
    var onFirstLayout: ((MLNMapView) -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0, let callback = onFirstLayout else { return }
        onFirstLayout = nil
        callback(self)
    }
}

extension UIColor {
    /// "#RRGGBB", for style expressions that read a colour from a feature.
    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
