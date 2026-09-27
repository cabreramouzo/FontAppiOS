import MapKit

/// The base maps the map can show. Port of `web/src/lib/mapLayers.ts`, adapted to iOS:
///
/// - Apple's standard and satellite maps are native and free, and stand in for the web's
///   OSM and Esri layers (OSM's tile servers ask apps not to lean on them; Esri's imagery
///   terms are for web viewers).
/// - ICGC and IGN keep their own layers, which is why they exist: the IGN MTN labels the
///   fountains with their place name, and the PNOA orthophoto is what lets someone place a
///   pin under trees, where GPS fails. They are raster here: MapKit cannot draw vector
///   tiles (see the vector spike for what that would take).
/// - IGN layers cover Spain only; outside they are blank, hence "(ES)" in their names.
nonisolated enum MapLayer: String, CaseIterable, Identifiable, Sendable {
    case apple, appleSatellite, icgc, mtn, pnoa, openTopo

    var id: String { rawValue }

    /// Tile URL template for raster layers; `nil` for Apple's own.
    var tileTemplate: String? {
        switch self {
        case .apple, .appleSatellite:
            nil
        case .icgc:
            "https://geoserveis.icgc.cat/servei/catalunya/mapa-base/wmts/topografic/MON3857NW/{z}/{x}/{y}.png"
        case .mtn:
            "https://www.ign.es/wmts/mapa-raster?service=WMTS&request=GetTile&version=1.0.0&layer=MTN&style=default&tilematrixset=GoogleMapsCompatible&format=image/jpeg&tilematrix={z}&tilerow={y}&tilecol={x}"
        case .pnoa:
            "https://www.ign.es/wmts/pnoa-ma?service=WMTS&request=GetTile&version=1.0.0&layer=OI.OrthoimageCoverage&style=default&tilematrixset=GoogleMapsCompatible&format=image/jpeg&tilematrix={z}&tilerow={y}&tilecol={x}"
        case .openTopo:
            "https://tile.opentopomap.org/{z}/{x}/{y}.png"
        }
    }

    var maxZoom: Int {
        switch self {
        case .apple, .appleSatellite, .pnoa: 19
        case .icgc, .mtn: 18
        case .openTopo: 17
        }
    }

    /// Whether its tiles may be saved for offline use. ICGC and IGN publish under
    /// CC BY 4.0; OpenTopoMap asks not to be bulk-downloaded, and Apple's cannot be saved.
    var canSaveOffline: Bool {
        switch self {
        case .icgc, .mtn, .pnoa: true
        case .apple, .appleSatellite, .openTopo: false
        }
    }

    /// Web dictionary key, except Apple's, which have app-only names.
    var labelKey: String {
        switch self {
        case .apple: "ios.layer.apple"
        case .appleSatellite: "layer.satellite"
        case .icgc: "layer.icgc"
        case .mtn: "layer.mtn"
        case .pnoa: "layer.pnoa"
        case .openTopo: "layer.topo"
        }
    }

    var systemImage: String {
        switch self {
        case .apple: "map"
        case .appleSatellite: "globe.europe.africa.fill"
        case .icgc, .mtn, .openTopo: "mountain.2"
        case .pnoa: "photo"
        }
    }

    /// Credit for the base map, shown on the map. Apple credits its own maps.
    var attribution: String? {
        switch self {
        case .apple, .appleSatellite: nil
        case .icgc: "© ICGC (CC BY 4.0) · © OpenStreetMap"
        case .mtn: "MTN © IGN (CC BY 4.0)"
        case .pnoa: "PNOA © IGN (CC BY 4.0)"
        case .openTopo: "© OpenStreetMap · © OpenTopoMap (CC BY-SA)"
        }
    }

    func tileURL(z: Int, x: Int, y: Int) -> URL? {
        guard let template = tileTemplate else { return nil }
        let text = template.replacingOccurrences(of: "{z}", with: String(z))
            .replacingOccurrences(of: "{x}", with: String(x))
            .replacingOccurrences(of: "{y}", with: String(y))
        return URL(string: text)
    }

    static let storageKey = "map.layer"

    static var saved: MapLayer {
        UserDefaults.standard.string(forKey: storageKey).flatMap(MapLayer.init(rawValue:)) ?? .apple
    }
}

/// A raster layer drawn over (and instead of) Apple's map.
///
/// Tiles go through a disk cache shared with the offline zones: what was seen once, or
/// saved on purpose, is shown without signal.
final class LayerTileOverlay: MKTileOverlay {
    let layer: MapLayer

    init(layer: MapLayer) {
        self.layer = layer
        super.init(urlTemplate: nil)
        canReplaceMapContent = true
        maximumZ = layer.maxZoom
        minimumZ = 0
    }

    override func url(forTilePath path: MKTileOverlayPath) -> URL {
        layer.tileURL(z: path.z, x: path.x, y: path.y) ?? URL(string: "about:blank")!
    }

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, (any Error)?) -> Void) {
        let layer = layer
        Task {
            do {
                result(try await TileStore.shared.tile(layer: layer, z: path.z, x: path.x, y: path.y), nil)
            } catch {
                result(nil, error)
            }
        }
    }
}
