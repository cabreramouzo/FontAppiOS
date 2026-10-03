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
    /// The saved GPX routes that are not hidden, each in its colour.
    var routes: [MapRoute] = []
    /// A route line was tapped (and no fountain was under the finger): opens its sheet.
    var onSelectRoute: ((UUID) -> Void)?
    /// The fountain whose sheet is open: drawn as a larger pin that springs in, so it is
    /// clear which one the sheet is about.
    var selected: FontSummary?

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
        // A tap on a pin selects at once, as in Apple Maps; anywhere else it waits for
        // MapLibre's double tap to zoom to fail (a third of a second), as before.
        tap.delegate = context.coordinator
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
        coordinator.update(map, fonts: fonts, clusters: clusters, routes: routes)
        coordinator.select(selected, on: map)
    }

    final class Coordinator: NSObject, MLNMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: FontMapView
        var followRequest = 0
        var shownLayer: MapLayer?
        private var placedInitialRegion = false
        /// Waiting for the first fix before following.
        private var wantsFollow = false

        private var fonts: [UUID: FontSummary] = [:]
        private var fontsSignature = 0
        private var serverClusters: [MapCluster] = []
        private var routes: [MapRoute] = []
        /// Our sources in the current style; nil until it has loaded.
        private var fontsSource: MLNShapeSource?
        private var clustersSource: MLNShapeSource?
        private var routeSource: MLNShapeSource?
        /// The raised pin standing in for the selected fountain's dot.
        private var selection: SelectedFountain?

        init(_ parent: FontMapView) {
            self.parent = parent
        }

        // MARK: Data

        func update(_ map: MLNMapView, fonts list: [FontSummary], clusters: [MapCluster],
                    routes newRoutes: [MapRoute]) {
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
            // Framing is the caller's: on import and when one is opened from the list. Here
            // it would jump the map every time a line is shown, hidden or recoloured.
            if newRoutes != routes {
                routes = newRoutes
                routeSource?.shape = routeShape()
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
            MLNShapeCollectionFeature(shapes: routes.compactMap { route in
                guard route.coordinates.count >= 2 else { return nil }
                var coordinates = route.coordinates
                let line = MLNPolylineFeature(coordinates: &coordinates, count: UInt(coordinates.count))
                line.attributes = ["color": String(format: "#%06X", route.colorHex), "route": route.id.uuidString]
                return line
            })
        }

        // MARK: Style

        /// Every style load (first one and each layer change) gets our sources and layers.
        func mapView(_ map: MLNMapView, didFinishLoading style: MLNStyle) {
            let font = Self.countFont(in: style)

            let routeSource = MLNShapeSource(identifier: "fa-route", shape: routeShape(), options: nil)
            style.addSource(routeSource)
            let routeLine = MLNLineStyleLayer(identifier: "fa-route-line", source: routeSource)
            // Each line carries its colour as "#RRGGBB", like the pins.
            routeLine.lineColor = NSExpression(format: "CAST(color, 'UIColor')")
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

            hideSelectedDot(in: style)

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

        // MARK: Selection

        func select(_ font: FontSummary?, on map: MLNMapView) {
            guard font?.id != selection?.font.id else { return }
            if let old = selection {
                selection = nil
                if let view = map.view(for: old) as? SelectedPinView {
                    view.lower { map.removeAnnotation(old) }
                } else {
                    map.removeAnnotation(old)
                }
            }
            if let font {
                let annotation = SelectedFountain(font: font)
                selection = annotation
                map.addAnnotation(annotation)
            }
            hideSelectedDot(in: map.style)
        }

        /// The dot under the raised pin would peek out around its tip.
        private func hideSelectedDot(in style: MLNStyle?) {
            let hidden = selection?.font.id.uuidString ?? ""
            for id in ["fa-pins", "fa-pin-drop"] {
                (style?.layer(withIdentifier: id) as? MLNVectorStyleLayer)?.predicate =
                    NSPredicate(format: "cluster != YES AND id != %@", hidden)
            }
        }

        func mapView(_ map: MLNMapView, viewFor annotation: MLNAnnotation) -> MLNAnnotationView? {
            guard let selected = annotation as? SelectedFountain else { return nil }
            let view = SelectedPinView(annotation: selected, reuseIdentifier: nil)
            view.configure(color: UIColor(WaterStatus.color(for: selected.font.lastWaterStatus)))
            return view
        }

        func mapView(_ map: MLNMapView, didAdd annotationViews: [MLNAnnotationView]) {
            for view in annotationViews { (view as? SelectedPinView)?.raise() }
        }

        // MARK: Taps

        /// Whether the finger came down on a fountain, decided when it touches.
        private var touchOnPin = false

        func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            if let map = gesture.view as? MLNMapView {
                let point = touch.location(in: map)
                let rect = CGRect(x: point.x - 22, y: point.y - 22, width: 44, height: 44)
                touchOnPin = map.visibleFeatures(in: rect, styleLayerIdentifiers: ["fa-pins", "fa-local", "fa-server"])
                    .contains { $0.attribute(forKey: "id") != nil && $0.attribute(forKey: "count") == nil && !($0 is MLNPointFeatureCluster) }
            }
            return true
        }

        func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldRequireFailureOf other: UIGestureRecognizer) -> Bool {
            !touchOnPin && (other as? UITapGestureRecognizer)?.numberOfTapsRequired == 2
        }

        func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }

        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let map = gesture.view as? MLNMapView else { return }
            let point = gesture.location(in: map)
            // A 44 pt target around the finger, as Apple asks, whatever the drawn size.
            let rect = CGRect(x: point.x - 22, y: point.y - 22, width: 44, height: 44)
            let hits = map.visibleFeatures(in: rect, styleLayerIdentifiers: ["fa-pins", "fa-local", "fa-server"])
            let nearest = hits.min { a, b in
                distance(map.convert(a.coordinate, toPointTo: map), point) < distance(map.convert(b.coordinate, toPointTo: map), point)
            }
            guard let hit = nearest else {
                // No fountain there: a route line, if one passes under the finger. Fountains
                // win: they sit on the line, and the route's sheet is one tap away anyway.
                let route = map.visibleFeatures(in: rect, styleLayerIdentifiers: ["fa-route-line"])
                    .compactMap { ($0.attribute(forKey: "route") as? String).flatMap(UUID.init(uuidString:)) }
                    .first
                if let route { parent.onSelectRoute?(route) }
                return
            }
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

/// A route line as the map needs it: equatable, so a redraw is skipped when nothing moved.
struct MapRoute: Equatable {
    let id: UUID
    let coordinates: [CLLocationCoordinate2D]
    let colorHex: Int

    static func == (a: MapRoute, b: MapRoute) -> Bool {
        // Coordinates of a saved route never change; its id and length stand for them.
        a.id == b.id && a.colorHex == b.colorHex && a.coordinates.count == b.coordinates.count
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

/// The selected fountain, as an annotation: the only one on the map.
final class SelectedFountain: MLNPointAnnotation {
    let font: FontSummary

    init(font: FontSummary) {
        self.font = font
        super.init()
        coordinate = CLLocationCoordinate2D(latitude: font.latitude, longitude: font.longitude)
    }

    required init?(coder: NSCoder) { fatalError("not coded") }
}

/// A balloon marker in the fountain's status colour with the drop inside, its tip on the
/// spot. It rises as Apple Maps raises a selected place: grows quickly from the tip with a
/// small settle, and a light tap in the hand. Reduce Motion: it just fades in.
final class SelectedPinView: MLNAnnotationView {
    private let head = UIView()
    private let tail = CAShapeLayer()
    private let glyph = UIImageView()
    private static let headSize: CGFloat = 46
    private static let tailHeight: CGFloat = 10

    override init(annotation: MLNAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        let size = Self.headSize
        frame = CGRect(x: 0, y: 0, width: size, height: size + Self.tailHeight)
        // The tip sits on the coordinate and it grows from there. The anchor alone does
        // it: MapLibre places the view's position, which the anchor makes the tip. A
        // `centerOffset` as well lifted the tip half a pin above the fountain.
        layer.anchorPoint = CGPoint(x: 0.5, y: 1)
        scalesWithViewingDistance = false
        isUserInteractionEnabled = false

        tail.path = {
            let path = UIBezierPath()
            path.move(to: CGPoint(x: size / 2 - 9, y: size - 6))
            path.addLine(to: CGPoint(x: size / 2, y: size + Self.tailHeight))
            path.addLine(to: CGPoint(x: size / 2 + 9, y: size - 6))
            path.close()
            return path.cgPath
        }()
        layer.addSublayer(tail)

        head.frame = CGRect(x: 0, y: 0, width: size, height: size)
        head.layer.cornerRadius = size / 2
        head.layer.borderColor = UIColor.white.cgColor
        head.layer.borderWidth = 3
        addSubview(head)

        glyph.image = UIImage(systemName: "drop.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .bold))
        glyph.tintColor = .white
        glyph.contentMode = .center
        glyph.frame = head.bounds
        head.addSubview(glyph)

        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.3
        layer.shadowRadius = 5
        layer.shadowOffset = CGSize(width: 0, height: 3)
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { fatalError("not coded") }

    func configure(color: UIColor) {
        head.backgroundColor = color
        tail.fillColor = color.cgColor
    }

    func raise() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        guard !UIAccessibility.isReduceMotionEnabled else {
            alpha = 0
            UIView.animate(withDuration: 0.2) { self.alpha = 1 }
            return
        }
        // As Apple Maps: a quick grow from the tip with a small settle, no dance. A
        // long bounce read as slow, and the sway moved the tip off the fountain.
        transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        alpha = 0
        UIView.animate(withDuration: 0.32, delay: 0, usingSpringWithDamping: 0.72, initialSpringVelocity: 0.6,
                       options: [.allowUserInteraction]) {
            self.transform = .identity
            self.alpha = 1
        }
    }

    func lower(_ done: @escaping () -> Void) {
        guard !UIAccessibility.isReduceMotionEnabled else { done(); return }
        UIView.animate(withDuration: 0.18, animations: {
            self.transform = CGAffineTransform(scaleX: 0.3, y: 0.3)
            self.alpha = 0
        }, completion: { _ in done() })
    }
}
