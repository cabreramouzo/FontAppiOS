import Foundation

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
