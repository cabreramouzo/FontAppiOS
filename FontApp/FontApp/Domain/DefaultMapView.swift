import Foundation
import MapKit

/// Where the map opens for someone we know nothing about yet (no location permission).
///
/// Guessed from the device time zone: no prompt, no network, nothing leaves the phone, and
/// it names the country far better than the language does. Only a starting point — the
/// user's location wins as soon as it is available. Port of `defaultViewFor` in
/// `web/src/lib/mapView.ts`; unknown zones fall back to Madrid at zoom 5.
nonisolated struct DefaultMapView: Equatable, Sendable {
    let latitude: Double
    let longitude: Double
    /// Web (Leaflet/OSM) zoom level, kept so the table reads the same as the web's.
    let zoom: Double

    static let fallback = DefaultMapView(latitude: 40.4168, longitude: -3.7038, zoom: 5)

    static func forTimeZone(_ identifier: String?) -> DefaultMapView {
        guard let identifier else { return fallback }
        if let view = byZone[identifier] { return view }
        if identifier == "America/Punta_Arenas" { return byZone["America/Santiago"]! }
        if identifier.hasPrefix("America/Argentina/") || identifier == "America/Buenos_Aires" { return argentina }
        let city = identifier.hasPrefix("America/") ? String(identifier.dropFirst(8)) : ""
        if mexican.contains(city) { return byZone["America/Mexico_City"]! }
        if brazilian.contains(city) { return brazil }
        return fallback
    }

    /// The region that shows what a web map of `size` points shows at this zoom.
    func region(for size: CGSize) -> MKCoordinateRegion {
        let width = max(size.width, 320)
        let height = max(size.height, 320)
        // Web Mercator: 256 px tiles, the world is 256·2^zoom px wide.
        let longitudeDelta = min(360 * width / (256 * pow(2, zoom)), 360)
        let latitudeDelta = min(longitudeDelta * height / width * cos(latitude * .pi / 180), 170)
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
        )
    }

    private static func v(_ lat: Double, _ lng: Double, _ zoom: Double) -> DefaultMapView {
        DefaultMapView(latitude: lat, longitude: lng, zoom: zoom)
    }

    private static let brazil = v(-14.2, -51.9, 4)
    private static let argentina = v(-38.4, -63.6, 4)
    private static let mexican: Set<String> = ["Cancun", "Merida", "Monterrey", "Matamoros", "Chihuahua",
        "Ciudad_Juarez", "Ojinaga", "Mazatlan", "Bahia_Banderas", "Hermosillo", "Tijuana"]
    private static let brazilian: Set<String> = ["Sao_Paulo", "Bahia", "Fortaleza", "Recife", "Belem",
        "Manaus", "Cuiaba", "Campo_Grande", "Porto_Velho", "Boa_Vista", "Rio_Branco", "Araguaina",
        "Maceio", "Santarem", "Noronha", "Eirunepe"]

    private static let byZone: [String: DefaultMapView] = [
        "America/Mexico_City": v(23.6, -102.5, 5),
        "America/Santiago": v(-35, -71, 5),
        "America/Lima": v(-9.2, -75, 5),
        "America/Guayaquil": v(-1.8, -78.2, 6),
        "America/Bogota": v(4.6, -74.3, 5),
        "America/La_Paz": v(-16.3, -63.6, 5),
        "America/Montevideo": v(-32.5, -55.8, 6),
        "America/Asuncion": v(-23.4, -58.4, 6),
        "America/Caracas": v(6.4, -66.6, 5),
        "America/Havana": v(21.5, -79.5, 6),
        "America/Costa_Rica": v(9.7, -84, 7),
        "America/Panama": v(8.5, -80.8, 7),
        "America/Managua": v(12.9, -85.2, 7),
        "America/Guatemala": v(15.8, -90.2, 7),
        "America/Tegucigalpa": v(15.2, -86.2, 7),
        "America/El_Salvador": v(13.8, -88.9, 8),
        "America/Santo_Domingo": v(18.7, -70.2, 7),
        "America/Puerto_Rico": v(18.2, -66.5, 8),
        "Europe/Rome": v(42.5, 12.5, 5),
        "Europe/Paris": v(46.6, 2.2, 5),
        "Europe/Lisbon": v(39.6, -8, 6),
        "Europe/Zurich": v(46.8, 8.2, 7),
        "Europe/Stockholm": v(62, 15, 4),
        "Europe/Helsinki": v(64, 26, 4),
        "Europe/London": v(54.5, -3, 5),
        "Europe/Dublin": v(53.4, -8, 6),
        "Europe/Berlin": v(51.2, 10.4, 6),
        "Europe/Budapest": v(47.2, 19.4, 7),
        "Europe/Vienna": v(47.6, 14.1, 7),
        "Europe/Athens": v(38.6, 23.5, 6),
        "Europe/Prague": v(49.8, 15.5, 7),
        "Europe/Podgorica": v(42.7, 19.3, 8),
        "Europe/Amsterdam": v(52.2, 5.3, 7),
        "Europe/Warsaw": v(52, 19.1, 6),
        "Europe/Ljubljana": v(46.1, 14.8, 8),
        "Europe/Zagreb": v(45.1, 15.2, 7),
        "Europe/Sarajevo": v(44, 17.8, 7),
        "Europe/Brussels": v(50.6, 4.6, 8),
        "Europe/Tirane": v(41.2, 20.1, 8),
        "Europe/Busingen": v(51.2, 10.4, 6),
        "Asia/Tokyo": v(36.5, 138, 5),
        "Europe/Sofia": v(42.7, 25.3, 7),
        "Europe/Bratislava": v(48.7, 19.7, 7),
        "Europe/Bucharest": v(45.9, 25, 6),
        "Europe/Belgrade": v(44, 20.9, 7),
        "Europe/Copenhagen": v(56, 10.5, 6),
        "Europe/Skopje": v(41.6, 21.7, 8),
        "Asia/Nicosia": v(35, 33.2, 8),
        "Asia/Famagusta": v(35, 33.2, 8),
        "Europe/Riga": v(56.9, 24.6, 7),
        "Europe/Vilnius": v(55.2, 23.9, 7),
        "Europe/Tallinn": v(58.7, 25, 7),
        "Europe/Luxembourg": v(49.8, 6.1, 9),
        "Atlantic/Reykjavik": v(64.9, -18.6, 6),
        "Europe/Vaduz": v(47.15, 9.55, 11),
        "Europe/San_Marino": v(43.94, 12.46, 12),
        "Europe/Monaco": v(43.74, 7.42, 14),
        "Europe/Malta": v(35.9, 14.4, 10),
        "America/New_York": v(39.5, -98.5, 4),
        "America/Chicago": v(39.5, -98.5, 4),
        "America/Denver": v(39.5, -98.5, 4),
        "America/Phoenix": v(34.2, -111.7, 6),
        "America/Los_Angeles": v(39.5, -98.5, 4),
        "America/Detroit": v(39.5, -98.5, 4),
        "America/Indiana/Indianapolis": v(39.5, -98.5, 4),
        "America/Boise": v(39.5, -98.5, 4),
        "America/Anchorage": v(62, -150, 4),
        "Pacific/Honolulu": v(20.8, -157.5, 7),
        "America/Toronto": v(50, -85, 4),
        "America/Vancouver": v(53, -123, 5),
        "America/Edmonton": v(54, -114, 5),
        "America/Winnipeg": v(52, -97, 5),
        "America/Regina": v(52, -106, 5),
        "America/Halifax": v(45, -63, 6),
        "America/St_Johns": v(48.5, -56, 6),
        "America/Moncton": v(46.5, -65.5, 7),
        "Europe/Oslo": v(62, 10, 4),
        "Arctic/Longyearbyen": v(62, 10, 4),
        "Europe/Andorra": v(42.5, 1.55, 10),
    ]
}
