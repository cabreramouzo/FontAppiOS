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

    /// The saved route it shows, in the route library.
    let savedID: UUID?
    var name: String
    let points: [GPX.Point]
    let lengthKm: Double
    private(set) var state: State = .loading
    var corridor: Double = GPX.corridor {
        didSet { recompute(); onChoiceChange?() }
    }
    private(set) var onRoute: [GPX.OnRoute] = []
    /// The ones left out of the GPS file. The EXCLUDED and not the chosen: widening the
    /// corridor brings new fountains, and they must come in chosen. "All" is the empty set.
    private(set) var excluded = Set<UUID>() {
        didSet { onChoiceChange?() }
    }
    /// The corridor or the choice changed: the library stores it with the route.
    @ObservationIgnored var onChoiceChange: (() -> Void)?
    let profile: [GPX.ProfilePoint]

    @ObservationIgnored private var candidates: [FontSummary] = []
    @ObservationIgnored private let api: APIClient

    init(name: String, points: [GPX.Point], corridor: Double = GPX.corridor, excluded: Set<UUID> = [],
         savedID: UUID? = nil, api: APIClient = .shared) {
        self.savedID = savedID
        self.name = name
        self.corridor = corridor
        self.excluded = excluded
        self.points = GPX.simplified(points)
        lengthKm = GPX.lengthKm(self.points)
        profile = GPX.profile(self.points)
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

    // MARK: Choosing what goes to the GPS unit

    /// Choosing hides nothing: the list, the profile and the dry stretches stay the whole
    /// route; this only decides the file.
    var chosen: [GPX.OnRoute] { onRoute.filter { !excluded.contains($0.id) } }

    func isChosen(_ stop: GPX.OnRoute) -> Bool { !excluded.contains(stop.id) }

    func toggle(_ stop: GPX.OnRoute) {
        if excluded.remove(stop.id) == nil { excluded.insert(stop.id) }
    }

    /// "Only from here": you leave home with a full bottle. By position in the list, not
    /// by kilometre: two fountains can share a kilometre to the decimal.
    func onlyFrom(_ stop: GPX.OnRoute) {
        guard let index = onRoute.firstIndex(where: { $0.id == stop.id }) else { return }
        excluded = Set(onRoute[..<index].map(\.id))
    }

    func chooseAll() { excluded = [] }
    func chooseNone() { excluded = Set(onRoute.map(\.id)) }

    /// The dry stretch with the most climbing.
    var driestClimb: (stretch: GPX.DryStretch, meters: Int)? {
        GPX.longestDryClimb(fountainKms: onRoute.map(\.km), lengthKm: lengthKm, profile: profile)
    }

    /// The longest stretch without any fountain, and — the figure that decides one bottle
    /// or two — counting only those where water is on record.
    var driest: GPX.DryStretch { GPX.driest(fountainKms: onRoute.map(\.km), lengthKm: lengthKm) }

    var driestWithWater: GPX.DryStretch {
        GPX.driest(fountainKms: onRoute.filter { Confidence.hasWaterOnRecord($0.font.evidence) }.map(\.km),
                   lengthKm: lengthKm)
    }

    /// Only the chosen fountains, with their kilometre and detour in the description.
    func gpx() -> String {
        GPX.build(chosen.map { stop in
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
