import Foundation
import OSLog

/// Every fountain the map has shown, kept on the phone, and which areas are known.
///
/// The map used to ask the server each time it stopped moving, even to show again what
/// it had just shown. Now a view shows the pins it already knows at once, and only asks
/// when part of it has not been loaded in the last `freshFor`. A pin rarely changes;
/// when it does (someone reviews it), a quarter of an hour late is fine, and your own
/// contributions refresh the view straight away.
///
/// Without signal the same pins stay, anywhere you have looked before, not only in the
/// zones saved on purpose.
nonisolated final class PinCache: @unchecked Sendable {
    static let shared = PinCache()
    static let freshFor: TimeInterval = 15 * 60
    /// About 10 MB of JSON: far more than anyone looks at, and bounded.
    static let maxPins = 40_000
    static let maxAreas = 60

    struct Area: Codable, Sendable {
        let box: Box
        let loadedAt: Date
    }

    /// `MapBox` without its validating initialiser, so it can be stored.
    struct Box: Codable, Equatable, Sendable {
        let minLat, maxLat, minLong, maxLong: Double

        init(_ b: MapBox) { minLat = b.minLat; maxLat = b.maxLat; minLong = b.minLong; maxLong = b.maxLong }

        func contains(_ b: MapBox) -> Bool {
            b.minLat >= minLat && b.maxLat <= maxLat && b.minLong >= minLong && b.maxLong <= maxLong
        }

        func contains(_ b: Box) -> Bool {
            b.minLat >= minLat && b.maxLat <= maxLat && b.minLong >= minLong && b.maxLong <= maxLong
        }
    }

    private struct Stored: Codable {
        var pins: [FontSummary]
        var seen: [UUID: Date]
        var areas: [Area]
    }

    private let lock = NSLock()
    private var pins: [UUID: FontSummary] = [:]
    private var seen: [UUID: Date] = [:]
    private var areas: [Area] = []
    private let file: URL?
    private var saveTask: Task<Void, Never>?
    private let log = Logger(subsystem: "net.fontapp.FontApp", category: "pins")

    /// `file` nil keeps everything in memory (tests).
    init(file: URL? = URL.cachesDirectory.appending(path: "pins.json")) {
        self.file = file
        if let file, let data = try? Data(contentsOf: file),
           let stored = try? JSONDecoder().decode(Stored.self, from: data) {
            pins = Dictionary(stored.pins.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            seen = stored.seen
            areas = stored.areas
        }
    }

    /// The known pins inside a view.
    func fonts(in box: MapBox) -> [FontSummary] {
        lock.withLock {
            pins.values.filter {
                $0.latitude >= box.minLat && $0.latitude <= box.maxLat
                    && $0.longitude >= box.minLong && $0.longitude <= box.maxLong
            }
        }
    }

    /// The view lies inside an area loaded recently: what is known is what there is.
    func isFresh(_ box: MapBox, now: Date = .now) -> Bool {
        lock.withLock { areas.contains { now.timeIntervalSince($0.loadedAt) < Self.freshFor && $0.box.contains(box) } }
    }

    /// A server answer for a view. Only individual pins make the area known: an answer
    /// with clusters leaves most fountains out.
    func store(_ response: MapResponse, for box: MapBox, now: Date = .now) {
        lock.withLock {
            // What the server no longer lists inside the area is gone (deleted, hidden).
            if response.clusters.isEmpty {
                let listed = Set(response.fonts.map(\.id))
                for (id, pin) in pins where !listed.contains(id)
                    && pin.latitude >= box.minLat && pin.latitude <= box.maxLat
                    && pin.longitude >= box.minLong && pin.longitude <= box.maxLong {
                    pins[id] = nil
                    seen[id] = nil
                }
                areas.removeAll { Box(box).contains($0.box) }
                areas.append(Area(box: Box(box), loadedAt: now))
                if areas.count > Self.maxAreas { areas.removeFirst(areas.count - Self.maxAreas) }
            }
            for font in response.fonts {
                pins[font.id] = font
                seen[font.id] = now
            }
            if pins.count > Self.maxPins {
                let oldest = seen.sorted { $0.value < $1.value }.prefix(pins.count - Self.maxPins)
                for (id, _) in oldest { pins[id] = nil; seen[id] = nil }
            }
        }
        scheduleSave()
    }

    /// A deleted fountain: gone from what is known, so no view shows it again.
    func remove(_ id: UUID) {
        lock.withLock {
            pins[id] = nil
            seen[id] = nil
        }
        scheduleSave()
    }

    /// After a contribution: the area is loaded again, whatever its age.
    func invalidate() {
        lock.withLock { areas.removeAll() }
        scheduleSave()
    }

    /// Written a moment after the last change, not on every pan.
    private func scheduleSave() {
        guard let file else { return }
        saveTask?.cancel()
        saveTask = Task.detached(priority: .utility) { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            let stored = self.lock.withLock { Stored(pins: Array(self.pins.values), seen: self.seen, areas: self.areas) }
            do {
                try JSONEncoder().encode(stored).write(to: file, options: .atomic)
            } catch {
                self.log.error("pins not saved: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
