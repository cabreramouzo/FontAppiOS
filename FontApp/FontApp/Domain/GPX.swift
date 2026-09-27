import CoreLocation
import Foundation

/// GPX in and out. Port of `web/src/lib/gpx.ts` and `web/src/lib/gpxImport.ts`.
///
/// The file never leaves the phone: a GPX is where someone moves, and it usually starts at
/// their door. Only the box around the route is asked of the server, which is the same as
/// moving the map there.
nonisolated enum GPX {
    struct Point: Equatable, Sendable {
        let latitude: Double
        let longitude: Double
        let elevation: Double?
    }

    /// Radius of the corridor around the route, by default and the choices.
    static let corridor: Double = 250
    static let corridors: [Double] = [100, 250, 500, 1000]
    /// Minimum spacing after simplifying: a Garmin logs a point a second, and at 25 m the
    /// route keeps its shape for distances of hundreds of metres.
    static let minStep: Double = 25
    /// Not ours: many GPS units take about this many and some cut the file silently.
    static let maxWaypoints = 500

    // MARK: Reading

    /// Track (`trkpt`) and route (`rtept`) points. `wpt` is ignored on purpose: they are
    /// the file's loose marks, not the path, and one in the wrong place shifts every distance.
    static func read(_ data: Data) -> [Point] {
        let reader = Reader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        parser.parse()
        return reader.points
    }

    private final class Reader: NSObject, XMLParserDelegate {
        var points: [Point] = []
        private var current: (lat: Double, lon: Double)?
        private var elevation: Double?
        private var inElevation = false
        private var text = ""

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            switch local(name) {
            case "trkpt", "rtept":
                guard let lat = attributes["lat"].flatMap(Double.init), let lon = attributes["lon"].flatMap(Double.init),
                      abs(lat) <= 90, abs(lon) <= 180 else { current = nil; return }
                current = (lat, lon)
                elevation = nil
            case "ele" where current != nil:
                inElevation = true
                text = ""
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if inElevation { text += string }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            switch local(name) {
            case "ele" where inElevation:
                inElevation = false
                elevation = Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
            case "trkpt", "rtept":
                if let current {
                    points.append(Point(latitude: current.lat, longitude: current.lon, elevation: elevation))
                }
                current = nil
            default:
                break
            }
        }

        private func local(_ name: String) -> String {
            name.split(separator: ":").last.map(String.init) ?? name
        }
    }

    // MARK: Geometry

    /// Metres between two points, flat local projection: enough at this scale.
    static func meters(_ a: Point, _ b: Point) -> Double {
        meters(a.latitude, a.longitude, b.latitude, b.longitude)
    }

    static func meters(_ aLat: Double, _ aLon: Double, _ bLat: Double, _ bLon: Double) -> Double {
        let rad = Double.pi / 180
        let x = (bLon - aLon) * rad * cos((aLat + bLat) / 2 * rad)
        let y = (bLat - aLat) * rad
        return (x * x + y * y).squareRoot() * 6_371_000
    }

    /// Drops points closer than `step` to the last one kept; keeps both ends.
    static func simplified(_ points: [Point], step: Double = minStep) -> [Point] {
        guard var last = points.first else { return [] }
        var out = [last]
        for point in points.dropFirst().dropLast() where meters(last, point) >= step {
            out.append(point)
            last = point
        }
        if points.count > 1, let end = points.last { out.append(end) }
        return out
    }

    static func lengthKm(_ points: [Point]) -> Double {
        zip(points, points.dropFirst()).reduce(0) { $0 + meters($1.0, $1.1) } / 1000
    }

    /// The box around the route, widened by the widest corridor: without the margin, a
    /// fountain beside the route falls outside the box and is never asked for — silently.
    /// The widest one so changing the corridor does not ask the server again.
    static func box(of points: [Point], margin: Double = corridors.max()!) -> MapBox? {
        guard let first = points.first else { return nil }
        var minLat = first.latitude, maxLat = first.latitude, minLon = first.longitude, maxLon = first.longitude
        for p in points {
            minLat = min(minLat, p.latitude); maxLat = max(maxLat, p.latitude)
            minLon = min(minLon, p.longitude); maxLon = max(maxLon, p.longitude)
        }
        let dLat = margin / 111_320
        let dLon = margin / (111_320 * max(0.05, cos((minLat + maxLat) / 2 * .pi / 180)))
        return MapBox(minLat: minLat - dLat, maxLat: maxLat + dLat, minLong: minLon - dLon, maxLong: maxLon + dLon)
    }

    struct OnRoute: Identifiable, Sendable {
        let font: FontSummary
        /// Kilometre of the route where it is closest.
        let km: Double
        /// Metres off the route.
        let detour: Int
        var id: UUID { font.id }
    }

    /// Fountains within `corridor` metres of the route, in the order they are reached
    /// (someone deciding where to stop decides in the order they ride).
    static func fountains(_ fonts: [FontSummary], along route: [Point], corridor: Double = corridor) -> [OnRoute] {
        guard route.count >= 2 else { return [] }
        var cumulative = [0.0]
        for i in 1..<route.count { cumulative.append(cumulative[i - 1] + meters(route[i - 1], route[i])) }
        var out: [OnRoute] = []
        for font in fonts {
            var best = Double.infinity, bestI = -1, bestT = 0.0
            for i in 1..<route.count {
                let a = route[i - 1], b = route[i]
                // Cheap rejection by latitude before the exact distance.
                if abs(a.latitude - font.latitude) * 111_000 > corridor + 2000,
                   abs(b.latitude - font.latitude) * 111_000 > corridor + 2000 { continue }
                let (distance, t) = toSegment(font.latitude, font.longitude, a, b)
                if distance < best { best = distance; bestI = i; bestT = t }
            }
            guard bestI > 0, best <= corridor else { continue }
            let segment = cumulative[bestI] - cumulative[bestI - 1]
            out.append(OnRoute(font: font, km: (cumulative[bestI - 1] + segment * bestT) / 1000,
                               detour: Int(best.rounded())))
        }
        return out.sorted { $0.km < $1.km }
    }

    /// Distance from a point to segment AB, and where along it (0…1), in local metres.
    private static func toSegment(_ lat: Double, _ lon: Double, _ a: Point, _ b: Point) -> (Double, Double) {
        let rad = Double.pi / 180
        let k = cos(lat * rad) * 111_320
        let ax = (a.longitude - lon) * k, ay = (a.latitude - lat) * 111_320
        let bx = (b.longitude - lon) * k, by = (b.latitude - lat) * 111_320
        let dx = bx - ax, dy = by - ay
        let length2 = dx * dx + dy * dy
        let t = length2 == 0 ? 0 : min(1, max(0, -(ax * dx + ay * dy) / length2))
        let px = ax + dx * t, py = ay + dy * t
        return ((px * px + py * py).squareRoot(), t)
    }

    struct DryStretch: Equatable, Sendable {
        let fromKm: Double
        let toKm: Double
        var lengthKm: Double { toKm - fromKm }
    }

    /// The longest stretch without a fountain. Both ends count: start to first fountain and
    /// last fountain to the end are dry stretches too, and the last one is ridden tired.
    static func driest(fountainKms: [Double], lengthKm: Double) -> DryStretch {
        let stops = [0] + fountainKms.filter { $0 >= 0 && $0 <= lengthKm }.sorted() + [lengthKm]
        var best = DryStretch(fromKm: 0, toKm: 0)
        for (a, b) in zip(stops, stops.dropFirst()) where b - a > best.lengthKm {
            best = DryStretch(fromKm: a, toKm: b)
        }
        return best
    }

    // MARK: Writing

    struct Waypoint: Sendable {
        let latitude: Double
        let longitude: Double
        let name: String
        let description: String?
    }

    /// A GPX of waypoints with Garmin's "Drinking Water" symbol (drops on the unit's screen
    /// instead of 500 identical flags). At most `maxWaypoints`.
    static func build(_ waypoints: [Waypoint]) -> String {
        let body = waypoints.prefix(maxWaypoints).map { w in
            var lines = [
                "  <wpt lat=\"\(coordinate(w.latitude))\" lon=\"\(coordinate(w.longitude))\">",
                "    <name>\(escape(w.name))</name>",
            ]
            if let description = w.description { lines.append("    <desc>\(escape(description))</desc>") }
            lines += ["    <sym>Drinking Water</sym>", "    <type>Water Source</type>", "  </wpt>"]
            return lines.joined(separator: "\n")
        }
        return ([
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
            "<gpx version=\"1.1\" creator=\"FontApp\"",
            "     xmlns=\"http://www.topografix.com/GPX/1/1\"",
            "     xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"",
            "     xsi:schemaLocation=\"http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd\">",
        ] + body + ["</gpx>"]).joined(separator: "\n") + "\n"
    }

    /// An unescaped `&` in a place name makes the unit reject the whole file. Control
    /// characters cannot be escaped in XML 1.0, so they go first, before the entities.
    static func escape(_ text: String) -> String {
        let clean = String(text.unicodeScalars.filter { s in
            !(s.value < 0x20 && s.value != 0x09 && s.value != 0x0A && s.value != 0x0D)
        })
        return clean.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    /// Seven decimals are about a centimetre: the format's convention.
    private static func coordinate(_ value: Double) -> String { String(format: "%.7f", value) }

    /// Dated, since several get downloaded and must be told apart.
    static func fileName(on date: Date = .now) -> String {
        "fontapp-\(date.formatted(.iso8601.year().month().day())).gpx"
    }

    /// When there are more fountains than a unit takes, the ones nearest the centre of the
    /// view stay: that is what was being looked at.
    static func nearestToCentre(_ fonts: [FontSummary], of box: MapBox) -> [FontSummary] {
        guard fonts.count > maxWaypoints else { return fonts }
        let lat = (box.minLat + box.maxLat) / 2, lon = (box.minLong + box.maxLong) / 2
        return Array(fonts.sorted {
            meters(lat, lon, $0.latitude, $0.longitude) < meters(lat, lon, $1.latitude, $1.longitude)
        }.prefix(maxWaypoints))
    }

    /// The type and last status with its date — or that nobody has ever checked it: a
    /// waypoint promising water that is not there has already made someone detour.
    static func description(of font: FontSummary, extra: String? = nil) -> String {
        var parts: [String] = []
        if let extra { parts.append(extra) }
        if let source = font.source { parts.append(L10n.t("source.\(source.rawValue)")) }
        if let status = WaterStatus(font.lastWaterStatus), let date = font.lastUpdate {
            parts.append("\(L10n.t(status.labelKey)) (\(date.formatted(date: .abbreviated, time: .omitted)))")
        } else {
            parts.append(L10n.t("gpx.unchecked"))
        }
        return parts.joined(separator: " · ")
    }
}

extension Confidence {
    /// Is it on record that this fountain has water, today and with backing? Both halves
    /// matter: a dry fountain is no place to fill a bottle, and one nobody has checked is
    /// a promise that fails the day you are thirsty. Port of `constaAgua`.
    nonisolated static func hasWaterOnRecord(_ e: ConfidenceEvidence, now: Date = .now) -> Bool {
        let level = level(of: e, now: now)
        guard level == .verified || level == .recent else { return false }
        return e.lastWaterStatus == "flowing" || e.lastWaterStatus == "trickle"
    }
}
