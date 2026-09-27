import Foundation

/// The base maps, as MapLibre styles. See `docs/vector-tiles.md`.
///
/// - The world map is OpenFreeMap: OpenStreetMap as vector tiles, free, no key, no limits,
///   offline downloads allowed (terms checked 27/09/2026). It replaces Apple's map, which
///   MapLibre cannot draw.
/// - ICGC and the IGN base map are vector: sharp at every zoom and ~30× lighter offline
///   than their raster (9.3 MB against 0.3 MB for Moià in ICGC).
/// - IGN MTN and PNOA stay raster, because that is what they are: the MTN labels fountains
///   with their place name, and the orthophoto lets someone place a pin under trees. IGN
///   layers cover Spain only, hence "(ES)".
nonisolated enum MapLayer: String, CaseIterable, Identifiable, Sendable {
    case world, icgc, ignBase, mtn, pnoa, openTopo

    var id: String { rawValue }

    var isVector: Bool {
        switch self {
        case .world, .icgc, .ignBase: true
        case .mtn, .pnoa, .openTopo: false
        }
    }

    /// The style to load. Raster layers get a small style written by the app.
    var styleURL: URL {
        switch self {
        case .world: URL(string: "https://tiles.openfreemap.org/styles/liberty")!
        case .icgc: URL(string: "https://geoserveis.icgc.cat/contextmaps/icgc.json")!
        case .ignBase: URL(string: "https://vt-mapabase.idee.es/files/styles/mapaBase_scn_color1_CNIG.json")!
        case .mtn, .pnoa, .openTopo: RasterStyle.url(for: self)
        }
    }

    /// Tile URL template for raster layers.
    var rasterTemplate: String? {
        switch self {
        case .mtn:
            "https://www.ign.es/wmts/mapa-raster?service=WMTS&request=GetTile&version=1.0.0&layer=MTN&style=default&tilematrixset=GoogleMapsCompatible&format=image/jpeg&tilematrix={z}&tilerow={y}&tilecol={x}"
        case .pnoa:
            "https://www.ign.es/wmts/pnoa-ma?service=WMTS&request=GetTile&version=1.0.0&layer=OI.OrthoimageCoverage&style=default&tilematrixset=GoogleMapsCompatible&format=image/jpeg&tilematrix={z}&tilerow={y}&tilecol={x}"
        case .openTopo:
            "https://tile.opentopomap.org/{z}/{x}/{y}.png"
        default:
            nil
        }
    }

    /// Deepest level the server has; MapLibre overzooms past it. For raster layers, in
    /// 256 px tiles as the servers count; for vector, the source's own maximum.
    var maxSourceZoom: Int {
        switch self {
        case .world: 14
        case .icgc: 15
        case .ignBase: 16
        case .mtn: 18
        case .pnoa: 19
        case .openTopo: 17
        }
    }

    /// Whether a zone's map may be downloaded. ICGC and IGN publish under CC BY 4.0 and
    /// OpenFreeMap allows it; OpenTopoMap asks not to be bulk-downloaded.
    var canSaveOffline: Bool { self != .openTopo }

    var labelKey: String {
        switch self {
        case .world: "ios.layer.world"
        case .icgc: "layer.icgc"
        case .ignBase: "ios.layer.ignBase"
        case .mtn: "layer.mtn"
        case .pnoa: "layer.pnoa"
        case .openTopo: "layer.topo"
        }
    }

    var systemImage: String {
        switch self {
        case .world: "map"
        case .icgc, .ignBase: "map.fill"
        case .mtn, .openTopo: "mountain.2"
        case .pnoa: "photo"
        }
    }

    /// Credit for the base map, shown on the map.
    var attribution: String {
        switch self {
        case .world: "© OpenFreeMap · © OpenMapTiles · © OpenStreetMap"
        case .icgc: "© ICGC (CC BY 4.0) · © OpenStreetMap"
        case .ignBase: "© IGN · SCNE (CC BY 4.0)"
        case .mtn: "MTN © IGN (CC BY 4.0)"
        case .pnoa: "PNOA © IGN (CC BY 4.0)"
        case .openTopo: "© OpenStreetMap · © OpenTopoMap (CC BY-SA)"
        }
    }

    static let storageKey = "map.layer"

    /// The saved choice. Apple's layers of earlier builds fall back to the world map.
    static var saved: MapLayer {
        UserDefaults.standard.string(forKey: storageKey).flatMap(MapLayer.init(rawValue:)) ?? .world
    }
}

/// A minimal style around a raster layer, written once to Application Support. Offline
/// packs keep the style URL, so the file must stay where it is.
nonisolated enum RasterStyle {
    static func url(for layer: MapLayer) -> URL {
        let directory = URL.applicationSupportDirectory.appending(path: "Styles", directoryHint: .isDirectory)
        let file = directory.appending(path: "\(layer.rawValue).json")
        if !FileManager.default.fileExists(atPath: file.path()), let json = json(for: layer) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? json.write(to: file, options: .atomic)
        }
        return file
    }

    static func json(for layer: MapLayer) -> Data? {
        guard let template = layer.rasterTemplate else { return nil }
        let style: [String: Any] = [
            "version": 8,
            "name": layer.rawValue,
            // Only for the counts on clusters: raster styles have no fonts of their own.
            "glyphs": "https://tiles.openfreemap.org/fonts/{fontstack}/{range}.pbf",
            "sources": [
                "base": [
                    "type": "raster", "tiles": [template], "tileSize": 256,
                    "maxzoom": layer.maxSourceZoom, "attribution": layer.attribution,
                ],
            ],
            "layers": [
                ["id": "background", "type": "background", "paint": ["background-color": "#f2efe9"]],
                ["id": "base", "type": "raster", "source": "base"],
            ],
        ]
        return try? JSONSerialization.data(withJSONObject: style, options: [.sortedKeys])
    }

    /// The font the counts on clusters use in raster styles.
    static let countFont = "Noto Sans Bold"
}
