import Foundation
import MapKit
import Observation

/// A zone saved on the phone for use without signal.
nonisolated struct OfflineZone: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    let savedAt: Date
    let minLat: Double, maxLat: Double, minLong: Double, maxLong: Double
    var fonts: [FontSummary]
    /// Map tiles saved with it, if any: which layer and which tiles.
    var tileLayer: MapLayer.RawValue?
    var tiles: [TileKey]
    var tileBytes: Int
    /// Photo paths (as the API gives them) saved as files.
    var photos: [String]
    var photoBytes: Int

    var box: MapBox? { MapBox(minLat: minLat, maxLat: maxLat, minLong: minLong, maxLong: maxLong) }

    func contains(latitude: Double, longitude: Double) -> Bool {
        latitude >= minLat && latitude <= maxLat && longitude >= minLong && longitude <= maxLong
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
        case .icgc: 150
        case .mtn, .pnoa: 22
        default: 30
        }
    }

    /// Politeness towards free tile servers, and a limit on what one tap can download.
    static let maxTiles = 2500
    static let extraZoomLevels = 2

    private(set) var zones: [OfflineZone] = []

    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let tiles: TileStore

    init(directory: URL? = nil, api: APIClient = .shared, tiles: TileStore = .shared) {
        self.directory = directory
            ?? URL.applicationSupportDirectory.appending(path: "OfflineZones", directoryHint: .isDirectory)
        self.api = api
        self.tiles = tiles
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        zones = (try? Data(contentsOf: indexURL)).flatMap { try? JSONDecoder().decode([OfflineZone].self, from: $0) } ?? []
    }

    // MARK: Using them without signal

    /// Saved fountains inside a box, from every zone that overlaps it.
    func fonts(in box: MapBox) -> [FontSummary] {
        var seen = Set<UUID>()
        return zones.flatMap { $0.fonts(in: box) }.filter { seen.insert($0.id).inserted }
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

    /// The tiles step two would download: this zoom and two more, capped.
    static func tilePlan(box: MapBox, zoom: Double, layer: MapLayer) -> [TileKey] {
        let first = max(0, min(Int(zoom.rounded(.down)), layer.maxZoom))
        let last = min(first + extraZoomLevels, layer.maxZoom)
        return (first...last).flatMap { TileKey.covering(box, zoom: $0) }
    }

    func saveTiles(_ plan: [TileKey], layer: MapLayer, for zoneID: UUID,
                   progress: @escaping (Int) -> Void) async throws {
        guard plan.count <= Self.maxTiles else { throw SaveError.tooMany }
        var bytes = 0
        var done = 0
        // A few at a time: fast enough, and gentle with a free server.
        try await withThrowingTaskGroup(of: Int.self) { group in
            var iterator = plan.makeIterator()
            for _ in 0..<6 {
                guard let tile = iterator.next() else { break }
                group.addTask { [tiles] in try await tiles.pin(layer: layer, z: tile.z, x: tile.x, y: tile.y) }
            }
            while let size = try await group.next() {
                bytes += size
                done += 1
                progress(done)
                if let tile = iterator.next() {
                    group.addTask { [tiles] in try await tiles.pin(layer: layer, z: tile.z, x: tile.x, y: tile.y) }
                }
            }
        }
        update(zoneID) {
            $0.tileLayer = layer.rawValue
            $0.tiles = plan
            $0.tileBytes = bytes
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
        if let raw = zone.tileLayer, let layer = MapLayer(rawValue: raw) {
            let stillUsed = Set(zones.filter { $0.tileLayer == raw }.flatMap(\.tiles))
            await tiles.unpin(layer: layer, tiles: zone.tiles.filter { !stillUsed.contains($0) })
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
