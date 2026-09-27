import CoreLocation
import Foundation
import Observation

/// "Water on my route": a GPX route and the fountains along it.
@Observable
final class RouteModel {
    enum State {
        case loading
        case loaded
        case failed(String)
    }

    let name: String
    let points: [GPX.Point]
    let lengthKm: Double
    private(set) var state: State = .loading
    var corridor: Double = GPX.corridor {
        didSet { recompute() }
    }
    private(set) var onRoute: [GPX.OnRoute] = []

    @ObservationIgnored private var candidates: [FontSummary] = []
    @ObservationIgnored private let api: APIClient

    init(name: String, points: [GPX.Point], api: APIClient = .shared) {
        self.name = name
        self.points = GPX.simplified(points)
        lengthKm = GPX.lengthKm(self.points)
        self.api = api
    }

    var coordinates: [CLLocationCoordinate2D] {
        points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    /// The fountains in the route's box, widened so the corridor can change without
    /// asking again. Falls back to saved zones without signal.
    func load() async {
        guard let box = GPX.box(of: points) else { return }
        do {
            candidates = try await api.fontsInBounds(box)
            recompute()
            state = .loaded
        } catch {
            let saved = OfflineZones.shared.fonts(in: box)
            if saved.isEmpty {
                state = .failed(ErrorText.describe(error))
            } else {
                candidates = saved
                recompute()
                state = .loaded
            }
        }
    }

    private func recompute() {
        onRoute = GPX.fountains(candidates, along: points, corridor: corridor)
    }

    /// The longest stretch without any fountain, and — the figure that decides one bottle
    /// or two — counting only those where water is on record.
    var driest: GPX.DryStretch { GPX.driest(fountainKms: onRoute.map(\.km), lengthKm: lengthKm) }

    var driestWithWater: GPX.DryStretch {
        GPX.driest(fountainKms: onRoute.filter { Confidence.hasWaterOnRecord($0.font.evidence) }.map(\.km),
                   lengthKm: lengthKm)
    }

    /// Only the route's fountains, with their kilometre and detour in the description.
    func gpx() -> String {
        GPX.build(onRoute.map { stop in
            GPX.Waypoint(latitude: stop.font.latitude, longitude: stop.font.longitude,
                         name: L10n.fontName(stop.font.name),
                         description: GPX.description(of: stop.font, extra: L10n.t("gpxIn.wptDesc", [
                             "km": Self.km(stop.km), "m": stop.detour,
                         ])))
        })
    }

    static func km(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }
}
