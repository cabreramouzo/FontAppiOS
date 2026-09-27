import Foundation

/// Raster tiles on disk, in two places:
///
/// - **Caches**: whatever was seen. iOS may empty it when space runs short, which is fine.
/// - **Application Support (pinned)**: tiles of zones saved for offline use. iOS never
///   deletes those on its own; they go when the zone is deleted.
///
/// A tile is looked up pinned first, then cached, then downloaded (and cached).
actor TileStore {
    static let shared = TileStore()

    /// The tile servers are free and run by others: say who is asking, as they request.
    static let userAgent = "FontApp-iOS/1.0 (+https://fontapp.net)"

    private let cacheRoot: URL
    private let pinnedRoot: URL
    private let session: URLSession

    init(cacheRoot: URL? = nil, pinnedRoot: URL? = nil) {
        self.cacheRoot = cacheRoot ?? URL.cachesDirectory.appending(path: "Tiles", directoryHint: .isDirectory)
        self.pinnedRoot = pinnedRoot
            ?? URL.applicationSupportDirectory.appending(path: "OfflineTiles", directoryHint: .isDirectory)
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = ["User-Agent": Self.userAgent]
        config.timeoutIntervalForRequest = 15
        // Our own disk store replaces URLCache for tiles.
        config.urlCache = nil
        config.httpMaximumConnectionsPerHost = 6
        session = URLSession(configuration: config)
    }

    func tile(layer: MapLayer, z: Int, x: Int, y: Int) async throws -> Data {
        let relative = Self.relativePath(layer: layer, z: z, x: x, y: y)
        for root in [pinnedRoot, cacheRoot] {
            if let data = try? Data(contentsOf: root.appending(path: relative)) { return data }
        }
        let data = try await download(layer: layer, z: z, x: x, y: y)
        write(data, to: cacheRoot.appending(path: relative))
        return data
    }

    /// Saves a tile for offline use. Returns its size in bytes (0 if it was already there).
    func pin(layer: MapLayer, z: Int, x: Int, y: Int) async throws -> Int {
        let relative = Self.relativePath(layer: layer, z: z, x: x, y: y)
        let target = pinnedRoot.appending(path: relative)
        if FileManager.default.fileExists(atPath: target.path()) { return 0 }
        let cached = cacheRoot.appending(path: relative)
        let data: Data
        if let local = try? Data(contentsOf: cached) {
            data = local
        } else {
            data = try await download(layer: layer, z: z, x: x, y: y)
        }
        write(data, to: target)
        return data.count
    }

    /// Removes pinned tiles. Tiles are shared between overlapping zones, so this is only
    /// called with the tiles no remaining zone needs.
    func unpin(layer: MapLayer, tiles: [TileKey]) {
        for tile in tiles {
            try? FileManager.default.removeItem(
                at: pinnedRoot.appending(path: Self.relativePath(layer: layer, z: tile.z, x: tile.x, y: tile.y)))
        }
    }

    private func download(layer: MapLayer, z: Int, x: Int, y: Int) async throws -> Data {
        guard let url = layer.tileURL(z: z, x: x, y: y) else { throw URLError(.badURL) }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, !data.isEmpty else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private func write(_ data: Data, to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    private static func relativePath(layer: MapLayer, z: Int, x: Int, y: Int) -> String {
        "\(layer.rawValue)/\(z)/\(x)/\(y)"
    }
}

/// A tile address in the Web Mercator grid.
nonisolated struct TileKey: Hashable, Codable, Sendable {
    let z: Int
    let x: Int
    let y: Int

    /// The tiles covering a box at one zoom level.
    static func covering(_ box: MapBox, zoom z: Int) -> [TileKey] {
        let n = Double(1 << z)
        func tileX(_ lon: Double) -> Int { Int(((lon + 180) / 360 * n).rounded(.down)) }
        func tileY(_ lat: Double) -> Int {
            let clamped = min(max(lat, -85.0511), 85.0511) * .pi / 180
            return Int(((1 - asinh(tan(clamped)) / .pi) / 2 * n).rounded(.down))
        }
        let maxIndex = (1 << z) - 1
        let x0 = max(0, tileX(box.minLong)), x1 = min(maxIndex, tileX(box.maxLong))
        let y0 = max(0, tileY(box.maxLat)), y1 = min(maxIndex, tileY(box.minLat))
        guard x0 <= x1, y0 <= y1 else { return [] }
        var keys: [TileKey] = []
        keys.reserveCapacity((x1 - x0 + 1) * (y1 - y0 + 1))
        for x in x0...x1 { for y in y0...y1 { keys.append(TileKey(z: z, x: x, y: y)) } }
        return keys
    }
}
