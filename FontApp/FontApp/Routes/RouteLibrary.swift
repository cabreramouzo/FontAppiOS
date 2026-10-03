import CoreData
import Foundation
import MapKit
import Observation
import SwiftData

/// The imported routes: every one not hidden is drawn on the map, and one at a time is
/// open (its fountains loaded, its chip on the map).
///
/// The routes live in SwiftData, synced through the person's private CloudKit database:
/// imported on the iPhone, they are on the iPad too. Without iCloud (signed out, or the
/// container not provisioned) the same store works on the device only. Name and colour
/// sync; which routes are hidden and which one is open are per device: hiding a route on
/// the iPad must not take it off the iPhone in someone's handlebar mount.
@MainActor @Observable
final class RouteLibrary {
    static let shared = RouteLibrary()
    static let cloudContainer = "iCloud.net.fontapp.FontApp"

    private(set) var routes: [SavedRoute] = []
    /// The open route, with its fountains.
    private(set) var active: RouteModel?
    /// Routes whose line is off the map. The hidden ones and not the shown ones: a route
    /// imported on another device arrives visible, as it did there.
    private(set) var hiddenIDs: Set<UUID> {
        didSet { defaults.set(hiddenIDs.map(\.uuidString), forKey: Keys.hidden) }
    }
    /// The map shows only the fountains along the visible routes: the lines and the water
    /// on them, without the town's other pins and the cluster bubbles over them. Every
    /// visible route and not only the open one: a trip in stages is several GPX files, and
    /// the fountains follow the lines on the map. Per device.
    var onlyRouteFonts: Bool {
        didSet { defaults.set(onlyRouteFonts, forKey: Keys.onlyRouteFonts) }
    }
    /// Fountains in each visible route's corridor, by route, for the routes not open (the
    /// open one uses its live list, which follows the corridor as it changes).
    private(set) var nearRoute: [UUID: [FontSummary]] = [:]

    /// The fountains the map shows, or nil for all of them. One fountain shared by two
    /// stages (where one ends and the next starts) is listed once.
    var routeFontsOnMap: [FontSummary]? {
        guard onlyRouteFonts, !visibleRoutes.isEmpty else { return nil }
        var seen = Set<UUID>()
        var fonts: [FontSummary] = []
        for saved in visibleRoutes {
            let near: [FontSummary]
            if let active, active.savedID == saved.id, case .loaded = active.state {
                near = active.onRoute.map(\.font)
            } else {
                near = nearRoute[saved.id] ?? []
            }
            for font in near where seen.insert(font.id).inserted { fonts.append(font) }
        }
        return fonts
    }

    /// Changes when the fountains along the routes have to be asked for again.
    var routeFontsKey: String {
        "\(onlyRouteFonts)|" + visibleRoutes.map(\.id.uuidString).joined(separator: ",")
    }
    /// What the map draws, oldest first so the newest line is on top.
    var visibleRoutes: [SavedRoute] { routes.reversed().filter { !hiddenIDs.contains($0.id) } }
    /// The store syncs with CloudKit; whether this device has an iCloud account is asked
    /// separately, since it can change while the app runs.
    let canSync: Bool

    var syncsWithICloud: Bool { canSync && FileManager.default.ubiquityIdentityToken != nil }

    /// Kept alive here: a ModelContext does not retain its container, and a context whose
    /// container is gone crashes on the first fetch.
    @ObservationIgnored private let container: ModelContainer?
    @ObservationIgnored private let context: ModelContext?
    @ObservationIgnored private let defaults: UserDefaults
    /// Off in tests: no fountains are asked of the server.
    @ObservationIgnored private let loadsFountains: Bool
    /// Decoded tracks: the map asks for them on every render, which follows the GPS.
    @ObservationIgnored private var coordinateCache: [UUID: [CLLocationCoordinate2D]] = [:]
    /// What the server answered for each route's box: the corridor can change without
    /// asking again.
    @ObservationIgnored private var candidates: [UUID: [FontSummary]] = [:]
    @ObservationIgnored private var remoteChanges: (any NSObjectProtocol)?

    private enum Keys {
        static let active = "routes.active"
        static let hidden = "routes.hiddenIDs"
        static let onlyRouteFonts = "routes.onlyRouteFonts"
    }

    init(inMemory: Bool = false, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadsFountains = !inMemory
        onlyRouteFonts = defaults.bool(forKey: Keys.onlyRouteFonts)
        hiddenIDs = Set((defaults.stringArray(forKey: Keys.hidden) ?? []).compactMap(UUID.init(uuidString:)))
        let schema = Schema([SavedRoute.self])
        var container: ModelContainer?
        var canSync = false
        if inMemory {
            container = try? ModelContainer(for: schema, configurations: ModelConfiguration(
                UUID().uuidString, schema: schema, isStoredInMemoryOnly: true))
        } else {
            do {
                container = try ModelContainer(for: schema, configurations: ModelConfiguration(
                    "Routes", schema: schema, cloudKitDatabase: .private(Self.cloudContainer)))
                canSync = true
            } catch {
                // The same file, without CloudKit: routes are kept, only not synced.
                container = try? ModelContainer(for: schema, configurations: ModelConfiguration(
                    "Routes", schema: schema, cloudKitDatabase: .none))
            }
        }
        self.canSync = canSync
        self.container = container
        context = container?.mainContext
        reload()
        if let id = defaults.string(forKey: Keys.active).flatMap(UUID.init(uuidString:)),
           let saved = routes.first(where: { $0.id == id }) {
            activate(saved)
        }
        // Routes imported or deleted on another device arrive in the background. Only the
        // CloudKit store sends them; an in-memory library has nothing to listen to.
        guard canSync else { return }
        remoteChanges = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    isolated deinit {
        if let remoteChanges { NotificationCenter.default.removeObserver(remoteChanges) }
    }

    /// Newest first. A route deleted elsewhere leaves the map here too.
    func reload() {
        guard let context else { return }
        let descriptor = FetchDescriptor<SavedRoute>(sortBy: [SortDescriptor(\.importedAt, order: .reverse)])
        routes = (try? context.fetch(descriptor)) ?? []
        if let id = active?.savedID {
            if let saved = routes.first(where: { $0.id == id }) {
                active?.name = saved.name
            } else {
                deactivate()
            }
        }
    }

    /// Saves a route read from a file and puts it on the map. The same track again is
    /// opened, not stored twice.
    @discardableResult
    func importRoute(name: String, points: [GPX.Point]) -> RouteModel {
        let simplified = GPX.simplified(points)
        let fingerprint = RouteCodec.fingerprint(simplified)
        if let existing = routes.first(where: { $0.fingerprint == fingerprint }) {
            return activate(existing)
        }
        let saved = SavedRoute(name: name, points: simplified, color: RouteColor.next(after: routes.count))
        if let context {
            context.insert(saved)
            save()
            reload()
        }
        return activate(saved)
    }

    @discardableResult
    func activate(_ saved: SavedRoute) -> RouteModel {
        setHidden(false, saved)
        if let active, active.savedID == saved.id { return active }
        let model = RouteModel(name: saved.name, points: saved.points, corridor: saved.corridor,
                               excluded: Set(saved.excluded), savedID: saved.id)
        model.onChoiceChange = { [weak self, weak model] in
            guard let self, let model, let saved = self.routes.first(where: { $0.id == model.savedID }) else { return }
            saved.corridor = model.corridor
            saved.excluded = Array(model.excluded)
            // Computed again with the new corridor when it is no longer the open one.
            self.nearRoute[saved.id] = nil
            self.save()
        }
        active = model
        defaults.set(saved.id.uuidString, forKey: Keys.active)
        if loadsFountains { Task { await model.load() } }
        return model
    }

    /// The fountains along each visible route not known yet: one request per route box
    /// (saved zones without signal), only while the switch is on. A route with no answer
    /// and nothing saved is tried again on the next change, never in a loop.
    func loadRouteFonts() async {
        guard onlyRouteFonts, loadsFountains else { return }
        for saved in visibleRoutes where nearRoute[saved.id] == nil {
            let points = saved.points
            guard let box = GPX.box(of: points) else { continue }
            let fonts: [FontSummary]
            if let known = candidates[saved.id] {
                fonts = known
            } else {
                do {
                    fonts = try await APIClient.shared.fontsInBounds(box)
                } catch {
                    let offline = OfflineZones.shared.fonts(in: box)
                    if offline.isEmpty { continue }
                    fonts = offline
                }
                candidates[saved.id] = fonts
            }
            nearRoute[saved.id] = GPX.fountains(fonts, along: points, corridor: saved.corridor).map(\.font)
        }
    }

    /// Closed: no chip and no fountains. The line stays if it is visible.
    func deactivate() {
        active = nil
        defaults.removeObject(forKey: Keys.active)
    }

    /// The lines to draw, each in its colour.
    var mapRoutes: [MapRoute] {
        visibleRoutes.map { saved in
            let coordinates = coordinateCache[saved.id] ?? {
                let decoded = saved.points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
                coordinateCache[saved.id] = decoded
                return decoded
            }()
            return MapRoute(id: saved.id, coordinates: coordinates, colorHex: saved.colorHex)
        }
    }

    func isHidden(_ saved: SavedRoute) -> Bool { hiddenIDs.contains(saved.id) }

    /// A hidden route is not left open: its chip would name a line that is not there.
    func setHidden(_ hidden: Bool, _ saved: SavedRoute) {
        if hidden {
            hiddenIDs.insert(saved.id)
            if isActive(saved) { deactivate() }
        } else {
            hiddenIDs.remove(saved.id)
        }
    }

    func setHidden(_ hidden: Bool, id: UUID) {
        if let saved = routes.first(where: { $0.id == id }) { setHidden(hidden, saved) }
    }

    func setColor(_ color: RouteColor, _ saved: SavedRoute) {
        saved.color = color
        save()
        // The map redraws from `routes`; a new array tells the view something changed.
        routes = routes
    }

    func savedRoute(id: UUID?) -> SavedRoute? { routes.first { $0.id == id } }

    func delete(_ saved: SavedRoute) {
        if active?.savedID == saved.id { deactivate() }
        hiddenIDs.remove(saved.id)
        coordinateCache[saved.id] = nil
        candidates[saved.id] = nil
        nearRoute[saved.id] = nil
        context?.delete(saved)
        save()
        reload()
    }

    func delete(id: UUID) {
        if let saved = routes.first(where: { $0.id == id }) { delete(saved) }
    }

    func rename(_ saved: SavedRoute, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        saved.name = name
        if active?.savedID == saved.id { active?.name = name }
        save()
        routes = routes
    }

    func isActive(_ saved: SavedRoute) -> Bool { active?.savedID == saved.id }

    /// The whole route, to fit the map to it.
    static func rect(of coordinates: [CLLocationCoordinate2D]) -> MKMapRect {
        coordinates.reduce(MKMapRect.null) {
            $0.union(MKMapRect(origin: MKMapPoint($1), size: MKMapSize(width: 0, height: 0)))
        }
    }

    private func save() {
        try? context?.save()
    }
}
