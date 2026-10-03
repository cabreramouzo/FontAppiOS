import Foundation
import SwiftData

/// An imported GPX route, kept on the device and in the person's own iCloud (CloudKit
/// private database). Never sent to FontApp's server.
///
/// CloudKit's rules for a synced model: every property has a default, nothing is unique,
/// no relationships. The track is stored as packed numbers, not as the original file: the
/// app only needs the simplified points, and they are a fraction of the size.
@Model
final class SavedRoute {
    var id: UUID = UUID()
    var name: String = ""
    var importedAt: Date = Date.now
    var lengthKm: Double = 0
    /// Corridor and the fountains left out of the GPS file: what the person chose for this
    /// route, so it is the same on every device.
    var corridor: Double = 250
    var excluded: [UUID] = []
    /// The line's colour, one of `RouteColor` (as 0xRRGGBB). Synced: the iPad draws the
    /// route in the colour chosen on the iPhone. Visibility is not, see `RouteLibrary`.
    var colorHex: Int = RouteColor.rose.rawValue
    /// Same track imported twice is opened, not duplicated.
    var fingerprint: String = ""
    @Attribute(.externalStorage) var pointData: Data = Data()

    init(name: String, points: [GPX.Point], color: RouteColor = .rose) {
        self.name = name
        colorHex = color.rawValue
        lengthKm = GPX.lengthKm(points)
        fingerprint = RouteCodec.fingerprint(points)
        pointData = RouteCodec.encode(points)
    }

    var points: [GPX.Point] { RouteCodec.decode(pointData) }

    /// A colour written by a newer app falls back to the first one instead of vanishing.
    var color: RouteColor {
        get { RouteColor(rawValue: colorHex) ?? .rose }
        set { colorHex = newValue.rawValue }
    }
}

/// A closed set and not any colour: a free picker gives lines in green, amber or red,
/// which on this map mean the state of the water. These six stay clear of the three
/// status colours and of each other, light and dark.
nonisolated enum RouteColor: Int, CaseIterable, Identifiable, Sendable {
    case rose = 0xE11D48, blue = 0x2563EB, indigo = 0x4338CA, cyan = 0x0891B2, pink = 0xDB2777, slate = 0x334155

    var id: Int { rawValue }
    var key: String {
        switch self {
        case .rose: "rose"
        case .blue: "blue"
        case .indigo: "indigo"
        case .cyan: "cyan"
        case .pink: "pink"
        case .slate: "slate"
        }
    }

    /// New routes take the next colour, so two routes on the map are told apart without
    /// anyone choosing anything.
    static func next(after count: Int) -> RouteColor { allCases[count % allCases.count] }
}

/// Packs a track as little-endian Float64 triples (latitude, longitude, elevation; NaN when
/// the point has no elevation): flat and unknown are not the same.
nonisolated enum RouteCodec {
    static func encode(_ points: [GPX.Point]) -> Data {
        var data = Data(capacity: points.count * 24)
        for point in points {
            for value in [point.latitude, point.longitude, point.elevation ?? .nan] {
                withUnsafeBytes(of: value.bitPattern.littleEndian) { data.append(contentsOf: $0) }
            }
        }
        return data
    }

    static func decode(_ data: Data) -> [GPX.Point] {
        guard data.count % 24 == 0 else { return [] }
        return data.withUnsafeBytes { raw in
            stride(from: 0, to: raw.count, by: 24).map { offset in
                func value(_ index: Int) -> Double {
                    Double(bitPattern: UInt64(littleEndian: raw.loadUnaligned(fromByteOffset: offset + index * 8, as: UInt64.self)))
                }
                let elevation = value(2)
                return GPX.Point(latitude: value(0), longitude: value(1), elevation: elevation.isNaN ? nil : elevation)
            }
        }
    }

    /// Count, ends and length: enough to tell the same track, cheap to compare.
    static func fingerprint(_ points: [GPX.Point]) -> String {
        guard let first = points.first, let last = points.last else { return "" }
        func round(_ v: Double) -> String { String(format: "%.5f", v) }
        return [String(points.count), round(first.latitude), round(first.longitude),
                round(last.latitude), round(last.longitude), String(format: "%.2f", GPX.lengthKm(points))]
            .joined(separator: "|")
    }
}
