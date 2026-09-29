import Foundation
import MapKit
import MapLibre
import Observation

/// A zone saved on the phone for use without signal.
nonisolated struct OfflineZone: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    let savedAt: Date
    let minLat: Double, maxLat: Double, minLong: Double, maxLong: Double
    var fonts: [FontSummary]
    /// Map saved with it, if any: which layer, and the size of its MapLibre offline pack
    /// (the pack is found by this zone's id in its context).
    var tileLayer: MapLayer.RawValue?
    /// Tiles saved by builds before MapLibre; kept only so old zones still decode.
    var tiles: [TileKey]
    var tileBytes: Int
    var tileResources: Int? = nil
    /// Photo paths (as the API gives them) saved as files.
    var photos: [String]
    var photoBytes: Int

    var box: MapBox? { MapBox(minLat: minLat, maxLat: maxLat, minLong: minLong, maxLong: maxLong) }

    func contains(latitude: Double, longitude: Double) -> Bool {
        latitude >= minLat && latitude <= maxLat && longitude >= minLong && longitude <= maxLong
    }

    /// Whether this zone can stand in for a view: it covers at least half of it. Zoomed out
    /// over a continent, a failed request must not swap the map for the dozen fountains of one
    /// saved valley, drawn as if those were all there are (the web's `zonaCubreLaVista`).
    func coversHalf(of box: MapBox) -> Bool {
        let width = min(maxLong, box.maxLong) - max(minLong, box.minLong)
        let height = min(maxLat, box.maxLat) - max(minLat, box.minLat)
        guard width > 0, height > 0 else { return false }
        let area = (box.maxLong - box.minLong) * (box.maxLat - box.minLat)
        return area > 0 && (width * height) / area >= 0.5
    }

    /// Its fountains inside a box, or none if the zone does not overlap it.
    func fonts(in box: MapBox) -> [FontSummary] {
        guard box.maxLat >= minLat, box.minLat <= maxLat, box.maxLong >= minLong, box.minLong <= maxLong else { return [] }
        return fonts.filter {
            $0.latitude >= box.minLat && $0.latitude <= box.maxLat
                && $0.longitude >= box.minLong && $0.longitude <= box.maxLong
        }
    }
}

/// The saved zones. Unlike the web (one zone, replaced each time), a phone can hold one
/// per outing. They live in Application Support, which iOS never clears on its own.
///
/// Rules kept from the web (`ZonaOfflineSheet.tsx`):
/// - the fountains are saved always and at once, which is what is needed on a mountain;
///   photos and map tiles are a second step, offered with their size, because they are two
///   orders of magnitude bigger and the count is only known after the fountains arrive;
/// - a zone without fountains is not saved: "0 saved" in green would send someone to the
///   mountain believing they carry it;
/// - of the map, what is on screen plus two zoom levels.
@Observable
final class OfflineZones {
    static let shared = OfflineZones()

    /// Estimated sizes, measured on 27/09/2026 over Moià (town and outskirts): the web's
    /// 489 KB per photo, and per tile of each layer. Shown as estimates.
    static let photoKB = 489
    static func tileKB(_ layer: MapLayer) -> Int {
        switch layer {
        case .icgc: 75
        case .world: 60
        case .ignBase: 21
        case .mtn: 13
        case .pnoa: 20
        case .openTopo: 30
        }
    }

    /// Politeness towards free tile servers, and a limit on what one tap can download.
    static let maxTiles = 2500
    static let extraZoomLevels = 2

    /// What step two would download: the zoom on screen and two more.
    struct TilePlan: Equatable {
        /// MapLibre zoom levels (512 px), as the offline pack takes them.
        let fromZoom: Int
        let toZoom: Int
        let tiles: Int
        var estimatedBytes: Int
    }

    /// Vector tiles stop at the source's own maximum (MapLibre overzooms past it, which is
    /// why vector zones are so light); raster ones are 256 px, one level deeper per zoom.
    static func tilePlan(box: MapBox, zoom: Double, layer: MapLayer) -> TilePlan {
        let first = max(0, Int(zoom.rounded(.down)))
        let last = first + extraZoomLevels
        let levels: [Int] = layer.isVector
            ? Array(Set((first...last).map { min($0, layer.maxSourceZoom) })).sorted()
            : Array(Set((first...last).map { min($0 + 1, layer.maxSourceZoom) })).sorted()
        let count = levels.reduce(0) { $0 + TileKey.covering(box, zoom: $1).count }
        return TilePlan(fromZoom: first, toZoom: last, tiles: count, estimatedBytes: count * tileKB(layer) * 1024)
    }

    private(set) var zones: [OfflineZone] = []

    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let api: APIClient

    init(directory: URL? = nil, api: APIClient = .shared) {
        self.directory = directory
            ?? URL.applicationSupportDirectory.appending(path: "OfflineZones", directoryHint: .isDirectory)
        self.api = api
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        zones = (try? Data(contentsOf: indexURL)).flatMap { try? JSONDecoder().decode([OfflineZone].self, from: $0) } ?? []
    }

    // MARK: Using them without signal

    /// Saved fountains inside a box, from every zone that overlaps it.
    func fonts(in box: MapBox) -> [FontSummary] {
        var seen = Set<UUID>()
        return zones.filter { $0.coversHalf(of: box) }.flatMap { $0.fonts(in: box) }.filter { seen.insert($0.id).inserted }
    }

    func font(_ id: UUID) -> FontSummary? {
        for zone in zones { if let font = zone.fonts.first(where: { $0.id == id }) { return font } }
        return nil
    }

    /// A saved photo, as a file, for an image path from the API.
    func photoFile(for path: String?) -> URL? {
        guard let path, zones.contains(where: { $0.photos.contains(path) }) else { return nil }
        let file = photoURL(for: path)
        return FileManager.default.fileExists(atPath: file.path()) ? file : nil
    }

    /// A deleted fountain leaves the zones that had it (its photo file stays until the zone goes).
    func remove(font id: UUID) {
        var changed = false
        for i in zones.indices where zones[i].fonts.contains(where: { $0.id == id }) {
            zones[i].fonts.removeAll { $0.id == id }
            changed = true
        }
        if changed { save() }
    }

    // MARK: Saving

    enum SaveError: Error { case empty, tooMany }

    /// Step one: the fountains in the box. Throws `.empty` when there are none.
    func saveFountains(in box: MapBox, name: String) async throws -> OfflineZone {
        let fonts = try await api.fontsInBounds(box)
        guard !fonts.isEmpty else { throw SaveError.empty }
        let zone = OfflineZone(id: UUID(), name: name, savedAt: .now, minLat: box.minLat, maxLat: box.maxLat,
                               minLong: box.minLong, maxLong: box.maxLong, fonts: fonts, tileLayer: nil,
                               tiles: [], tileBytes: 0, photos: [], photoBytes: 0)
        zones.insert(zone, at: 0)
        save()
        return zone
    }

    enum PackError: Error { case failed }

    /// Downloads the zone's map as a MapLibre offline pack: tiles, and for vector styles
    /// the fonts and icons too, so it draws complete without signal. `progress` is 0…1.
    func saveTiles(_ plan: TilePlan, layer: MapLayer, for zoneID: UUID,
                   progress: @escaping (Double) -> Void) async throws {
        guard plan.tiles <= Self.maxTiles else { throw SaveError.tooMany }
        guard let zone = zones.first(where: { $0.id == zoneID }) else { return }
        let bounds = MLNCoordinateBounds(sw: CLLocationCoordinate2D(latitude: zone.minLat, longitude: zone.minLong),
                                         ne: CLLocationCoordinate2D(latitude: zone.maxLat, longitude: zone.maxLong))
        let region = MLNTilePyramidOfflineRegion(styleURL: layer.styleURL, bounds: bounds,
                                                 fromZoomLevel: Double(plan.fromZoom), toZoomLevel: Double(plan.toZoom))
        let context = Data(zoneID.uuidString.utf8)
        let pack: MLNOfflinePack = try await withCheckedThrowingContinuation { continuation in
            MLNOfflineStorage.shared.addPack(for: region, withContext: context) { pack, error in
                if let pack { continuation.resume(returning: pack) } else { continuation.resume(throwing: error ?? PackError.failed) }
            }
        }
        pack.resume()
        let result: MLNOfflinePackProgress = try await withCheckedThrowingContinuation { continuation in
            var observers: [any NSObjectProtocol] = []
            var finished = false
            func finish(_ outcome: Result<MLNOfflinePackProgress, any Error>) {
                guard !finished else { return }
                finished = true
                observers.forEach(NotificationCenter.default.removeObserver)
                continuation.resume(with: outcome)
            }
            observers.append(NotificationCenter.default.addObserver(
                forName: .MLNOfflinePackProgressChanged, object: pack, queue: .main) { _ in
                MainActor.assumeIsolated {
                    let p = pack.progress
                    if p.countOfResourcesExpected > 0 {
                        progress(Double(p.countOfResourcesCompleted) / Double(p.countOfResourcesExpected))
                    }
                    if pack.state == .complete { finish(.success(p)) }
                }
            })
            observers.append(NotificationCenter.default.addObserver(
                forName: .MLNOfflinePackError, object: pack, queue: .main) { _ in
                MainActor.assumeIsolated {
                    pack.suspend()
                    finish(.failure(PackError.failed))
                }
            })
        }
        update(zoneID) {
            $0.tileLayer = layer.rawValue
            $0.tileBytes = Int(result.countOfBytesCompleted)
            $0.tileResources = Int(result.countOfResourcesCompleted)
        }
    }

    func saveThePhotos(of zoneID: UUID, progress: @escaping (Int) -> Void) async throws {
        guard let zone = zones.first(where: { $0.id == zoneID }) else { return }
        let paths = zone.fonts.compactMap(\.image)
        var saved: [String] = []
        var bytes = 0
        for path in paths {
            guard let url = api.imageURL(path) else { continue }
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { continue }
            let file = photoURL(for: path)
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            saved.append(path)
            bytes += data.count
            progress(saved.count)
        }
        update(zoneID) {
            $0.photos = saved
            $0.photoBytes = bytes
        }
    }

    /// Deletes a zone, and the tiles and photos no other zone uses.
    func delete(_ zoneID: UUID) async {
        guard let zone = zones.first(where: { $0.id == zoneID }) else { return }
        zones.removeAll { $0.id == zoneID }
        save()
        // MapLibre shares tiles between packs and frees only what no pack uses.
        let context = Data(zoneID.uuidString.utf8)
        for pack in MLNOfflineStorage.shared.packs ?? [] where pack.context == context {
            await withCheckedContinuation { continuation in
                MLNOfflineStorage.shared.removePack(pack) { _ in continuation.resume() }
            }
        }
        let photosUsed = Set(zones.flatMap(\.photos))
        for path in zone.photos where !photosUsed.contains(path) {
            try? FileManager.default.removeItem(at: photoURL(for: path))
        }
    }

    func rename(_ zoneID: UUID, to name: String) {
        update(zoneID) { $0.name = name }
    }

    // MARK: Storage

    private var indexURL: URL { directory.appending(path: "zones.json") }

    private func photoURL(for path: String) -> URL {
        let name = path.split(separator: "/").last.map(String.init) ?? UUID().uuidString
        return directory.appending(path: "photos/\(name)")
    }

    private func update(_ id: UUID, _ change: (inout OfflineZone) -> Void) {
        guard let i = zones.firstIndex(where: { $0.id == id }) else { return }
        change(&zones[i])
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(zones) else { return }
        try? data.write(to: indexURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
