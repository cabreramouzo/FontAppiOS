import Foundation
import MapKit
import Observation
import OSLog

/// What the map shows and when it asks the server for more.
@Observable
final class MapModel {
    private(set) var fonts: [FontSummary] = []
    private(set) var clusters: [MapCluster] = []
    private(set) var isLoading = false
    /// Set by a 429. The map keeps what it had and reloads by itself afterwards.
    private(set) var rateLimitedUntil: Date?
    /// Last failure other than a 429, already translated. Cleared by the next success.
    private(set) var errorMessage: String?

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let log = Logger(subsystem: "net.fontapp.FontApp", category: "map")
    @ObservationIgnored private var throttle = ReloadThrottle()
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var pendingTask: Task<Void, Never>?
    @ObservationIgnored private var lastLoaded: (box: MapBox, width: Int, height: Int)?
    @ObservationIgnored private var lastSpan: MKCoordinateSpan?

    init(api: APIClient = .shared) {
        self.api = api
    }

    /// Called when the map stops moving.
    func mapDidMove(region: MKCoordinateRegion, size: CGSize, following: Bool) {
        guard let box = MapBox(region: region) else { return }
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        pendingTask?.cancel()
        pendingTask = nil
        // MapKit keeps following through a pinch, but a zoom is always the user's doing:
        // only a pan at the same scale counts as the map moving on its own.
        let zoomed = lastSpan.map { abs(log2(region.span.longitudeDelta / $0.longitudeDelta)) > 0.2 } ?? true
        lastSpan = region.span
        let automatic = following && !zoomed

        if let until = rateLimitedUntil, until > .now {
            schedule(at: until) { $0.load(box: box, width: width, height: height) }
            return
        }
        switch throttle.decide(following: automatic) {
        case .now:
            load(box: box, width: width, height: height)
        case .at(let date):
            schedule(at: date) { $0.load(box: box, width: width, height: height) }
        }
    }

    private func schedule(at date: Date, _ action: @escaping (MapModel) -> Void) {
        pendingTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, date.timeIntervalSinceNow)))
            guard !Task.isCancelled, let self else { return }
            action(self)
        }
    }

    private func load(box: MapBox, width: Int, height: Int) {
        // Same view as the last answer (a GPS fix that did not move the map, a sheet
        // that came and went): nothing new to ask for.
        if let last = lastLoaded, last.box == box, last.width == width, last.height == height { return }
        throttle.didRequest()
        log.debug("GET /fonts/map \(box.minLat),\(box.minLong) – \(box.maxLat),\(box.maxLong)")
        // Only the latest box matters; a slow answer for an old view must not land.
        loadTask?.cancel()
        isLoading = true
        loadTask = Task { [weak self, api] in
            do {
                let response = try await api.map(box: box, width: width, height: height)
                guard !Task.isCancelled, let self else { return }
                self.lastLoaded = (box, width, height)
                if self.fonts != response.fonts { self.fonts = response.fonts }
                if self.clusters != response.clusters { self.clusters = response.clusters }
                self.errorMessage = nil
                self.rateLimitedUntil = nil
                self.isLoading = false
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.isLoading = false
                // Keep the pins already on screen: an empty map reads as "no fountains".
                if let e = error as? APIError, e.status == 429 {
                    let until = Date.now.addingTimeInterval(e.retryAfter ?? 60)
                    self.rateLimitedUntil = until
                    self.schedule(at: until) { $0.load(box: box, width: width, height: height) }
                } else {
                    self.errorMessage = ErrorText.describe(error)
                }
            }
        }
    }
}
