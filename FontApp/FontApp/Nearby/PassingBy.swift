import CoreLocation
import CoreMotion
import Foundation
import Observation
import OSLog
import UserNotifications

/// "You are passing by a fountain: is it flowing?", answered from the notice itself.
///
/// All of it happens on the iPhone: iOS watches a few circles around fountains (region
/// monitoring, cheap on battery, works without signal) and the app posts a **local**
/// notice. The position is never sent to be stored, and no server push is involved:
/// on a mountain there is rarely signal for one to arrive anyway.
///
/// Opt-in from Settings only: it needs the "Always" location permission, which is asked
/// when the person turns it on and never before.
nonisolated enum PassingByRules {
    /// iOS allows 20 monitored regions per app: 19 fountains and the circle that says
    /// "you have moved on, choose again".
    static let fountainSlots = 19
    /// Region monitoring is not precise below this; the notice says "near", not "at".
    static let fountainRadius: CLLocationDistance = 100
    static let minRefreshRadius: CLLocationDistance = 500
    static let maxRefreshRadius: CLLocationDistance = 3000
    /// Someone else said so recently: asking again adds little.
    static let freshEnough: TimeInterval = 3 * 86_400
    static let sameFountainAgain: TimeInterval = 30 * 86_400
    /// About one notice per stretch of a walk, and a few a day at most.
    static let betweenNotices: TimeInterval = 20 * 60
    static let perDay = 3
    static let quietHours = 22..<24, earlyHours = 0..<7
    /// Passing in a car or a bus is not passing by: nobody stops to look. Motion
    /// activity from the last few minutes says so; without it, the speed of a fresh fix.
    static let travelLookBack: TimeInterval = 3 * 60
    /// About 30 km/h: faster than anyone on foot or most people cycling in town.
    static let travellingSpeed: CLLocationSpeed = 8.3
    static let freshFix: TimeInterval = 30

    /// The fountains worth watching around a point: those where a passer-by's answer
    /// matters most first (never checked, conflicting, old), then the rest, nearest first.
    static func choose(_ fonts: [FontSummary], around point: CLLocation, now: Date = .now) -> [FontSummary] {
        let useful = fonts.filter { font in
            guard let last = font.lastUpdate, font.lastWaterStatus != nil else { return true }
            return now.timeIntervalSince(last) > freshEnough || font.recentStatusConflict == true
        }
        func priority(_ f: FontSummary) -> Int {
            switch Confidence.level(of: f.evidence, now: now) {
            case .unverified, .disputed: 0
            case .stale: 1
            case .recent, .verified: 2
            }
        }
        func distance(_ f: FontSummary) -> CLLocationDistance {
            point.distance(from: CLLocation(latitude: f.latitude, longitude: f.longitude))
        }
        return Array(useful.sorted { (priority($0), distance($0)) < (priority($1), distance($1)) }
            .prefix(fountainSlots))
    }

    /// The circle that, when left, makes the app choose again: out to the farthest
    /// watched fountain, within bounds.
    static func refreshRadius(for chosen: [FontSummary], around point: CLLocation) -> CLLocationDistance {
        let farthest = chosen.map { point.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude)) }
            .max() ?? minRefreshRadius
        return min(max(farthest, minRefreshRadius), maxRefreshRadius)
    }

    /// Whether entering a fountain's circle is worth a notice now.
    static func shouldNotify(_ fontID: UUID, history: [PassingByNotice], now: Date = .now,
                             calendar: Calendar = .current) -> Bool {
        let hour = calendar.component(.hour, from: now)
        if quietHours.contains(hour) || earlyHours.contains(hour) { return false }
        if history.contains(where: { $0.fontID == fontID && now.timeIntervalSince($0.at) < sameFountainAgain }) {
            return false
        }
        if let last = history.map(\.at).max(), now.timeIntervalSince(last) < betweenNotices { return false }
        let today = history.filter { calendar.isDate($0.at, inSameDayAs: now) }.count
        return today < perDay
    }
}

/// What the phone knows about how the person is moving, reduced to what the rule needs.
nonisolated struct MotionSample: Equatable, Sendable {
    let at: Date
    let automotive: Bool
    /// Walking, running, cycling or standing still out of a vehicle.
    let onFoot: Bool
    let confident: Bool
}

extension PassingByRules {
    /// In a vehicle when entering the circle: the latest confident activity says so,
    /// or, with no activity to go by, a fresh fix is too fast. Parking and walking to
    /// the fountain counts as on foot, since that is the latest activity.
    static func isTravelling(motion: [MotionSample], speed: CLLocationSpeed?, now: Date = .now) -> Bool {
        let recent = motion.filter { $0.confident && now.timeIntervalSince($0.at) <= travelLookBack
            && ($0.automotive || $0.onFoot) }
        if let latest = recent.max(by: { $0.at < $1.at }) { return latest.automotive }
        guard let speed, speed >= 0 else { return false }
        return speed >= travellingSpeed
    }
}

nonisolated struct PassingByNotice: Codable, Equatable, Sendable {
    let fontID: UUID
    let at: Date
}

/// Watches the chosen fountains and posts the notices.
@Observable
final class PassingBy: NSObject, CLLocationManagerDelegate {
    static let shared = PassingBy()
    static let category = "passingBy"
    static let notSeenAction = "passingBy.notSeen"

    /// The person's choice in Settings.
    private(set) var isEnabled: Bool
    private(set) var authorization: CLAuthorizationStatus = .notDetermined

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private let motion = CMMotionActivityManager()
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let log = Logger(subsystem: "net.fontapp.FontApp", category: "passingBy")
    @ObservationIgnored private var locating: [CheckedContinuation<CLLocation?, Never>] = []
    /// The fountains being watched, for the notice's name and position.
    @ObservationIgnored private var watched: [String: FontSummary] = [:]

    private static let enabledKey = "passingBy.enabled"
    private static let historyKey = "passingBy.history"
    private static let watchedKey = "passingBy.watched"
    private static let refreshID = "passingBy.refresh"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Self.enabledKey)
        super.init()
        watched = (defaults.data(forKey: Self.watchedKey)
            .flatMap { try? JSONDecoder().decode([String: FontSummary].self, from: $0) }) ?? [:]
        // The delegate must exist at launch: a region event relaunches the app in the
        // background and is delivered here.
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        Self.registerCategory()
    }

    var hasAlways: Bool { authorization == .authorizedAlways }
    /// Turned on, but iOS will not wake the app: the switch shows how to fix it.
    var isBlocked: Bool { isEnabled && (authorization == .denied || authorization == .restricted
                                         || authorization == .authorizedWhenInUse) }

    /// From Settings. Asks for notices and "Always" the first time; turning it off stops
    /// every watch at once.
    func setEnabled(_ on: Bool) async {
        isEnabled = on
        defaults.set(on, forKey: Self.enabledKey)
        guard on else { stop(); return }
        await PushNotifications.shared.enable()
        // iOS only offers "Always" after "While using": ask in that order.
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if manager.authorizationStatus == .authorizedWhenInUse {
            manager.requestAlwaysAuthorization()
        }
        await refresh()
    }

    /// Motion & Fitness has not been asked yet: Settings explains why before asking.
    var needsMotionAsk: Bool {
        CMMotionActivityManager.isActivityAvailable() && CMMotionActivityManager.authorizationStatus() == .notDetermined
    }

    /// Asks Motion & Fitness (the first query is what asks) and waits for the answer.
    /// Optional: with a "no", the speed of a fix still catches most drives.
    func askMotion() async {
        guard needsMotionAsk else { return }
        _ = await recentMotion()
    }

    /// Signing out: nothing can be sent without an account, so nothing is asked.
    func signedOut() {
        guard isEnabled else { return }
        isEnabled = false
        defaults.set(false, forKey: Self.enabledKey)
        stop()
    }

    /// Chooses the fountains around where the person is now and watches them.
    func refresh() async {
        guard isEnabled, hasAlways else { return }
        guard let here = await currentLocation() else { return }
        let fonts = await candidates(around: here)
        let chosen = PassingByRules.choose(fonts, around: here)
        for region in manager.monitoredRegions { manager.stopMonitoring(for: region) }
        watched = Dictionary(uniqueKeysWithValues: chosen.map { ($0.id.uuidString, $0) })
        defaults.set(try? JSONEncoder().encode(watched), forKey: Self.watchedKey)
        for font in chosen {
            let region = CLCircularRegion(center: CLLocationCoordinate2D(latitude: font.latitude, longitude: font.longitude),
                                          radius: PassingByRules.fountainRadius, identifier: font.id.uuidString)
            region.notifyOnEntry = true
            region.notifyOnExit = false
            manager.startMonitoring(for: region)
        }
        let refresh = CLCircularRegion(center: here.coordinate,
                                       radius: PassingByRules.refreshRadius(for: chosen, around: here),
                                       identifier: Self.refreshID)
        refresh.notifyOnEntry = false
        refresh.notifyOnExit = true
        manager.startMonitoring(for: refresh)
        log.info("watching \(chosen.count) fountains")
    }

    private func stop() {
        for region in manager.monitoredRegions { manager.stopMonitoring(for: region) }
        watched = [:]
        defaults.removeObject(forKey: Self.watchedKey)
    }

    /// Nearby fountains from the server, asked with the position rounded to about a
    /// kilometre; without signal, from the zones saved for offline use.
    private func candidates(around here: CLLocation) async -> [FontSummary] {
        let lat = (here.coordinate.latitude * 100).rounded() / 100
        let lon = (here.coordinate.longitude * 100).rounded() / 100
        if let fonts = try? await APIClient.shared.nearby(latitude: lat, longitude: lon, quantity: 60) {
            return fonts
        }
        let d = 0.03
        guard let box = MapBox(minLat: here.coordinate.latitude - d, maxLat: here.coordinate.latitude + d,
                               minLong: here.coordinate.longitude - d, maxLong: here.coordinate.longitude + d) else { return [] }
        return OfflineZones.shared.fonts(in: box)
    }

    private func currentLocation() async -> CLLocation? {
        await withCheckedContinuation { continuation in
            locating.append(continuation)
            if locating.count == 1 { manager.requestLocation() }
        }
    }

    private func finishLocating(_ location: CLLocation?) {
        let waiting = locating
        locating = []
        for continuation in waiting { continuation.resume(returning: location) }
    }

    // MARK: Notices

    /// Debug builds can pretend it is midday (`-PassingByMidday`), to try the notice at
    /// any hour; release builds always use the real time.
    private static var clock: Date {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-PassingByMidday") {
            return Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: .now) ?? .now
        }
        #endif
        return .now
    }

    private var history: [PassingByNotice] {
        (defaults.data(forKey: Self.historyKey)
            .flatMap { try? JSONDecoder().decode([PassingByNotice].self, from: $0) }) ?? []
    }

    private func entered(_ id: String) async {
        guard let font = watched[id], Outbox.shared.currentUserID != nil else { return }
        var history = self.history   // only the last month is kept: all the rules look at
        guard PassingByRules.shouldNotify(font.id, history: history, now: Self.clock) else {
            log.info("near \(id, privacy: .public): the rules say not now")
            return
        }
        // Checked after the cheap rules and before noting it: driving past must not use
        // up the fountain's turn for when the person walks by.
        if await isTravelling() {
            log.info("near \(id, privacy: .public): in a vehicle, no notice")
            return
        }
        log.info("near \(id, privacy: .public): notice")
        // Noted before posting: several circles often overlap, iOS reports them at the
        // same instant, and each must see that this one already took the turn.
        history.append(PassingByNotice(fontID: font.id, at: Self.clock))
        let kept = history.filter { Self.clock.timeIntervalSince($0.at) < PassingByRules.sameFountainAgain }
        defaults.set(try? JSONEncoder().encode(kept), forKey: Self.historyKey)
        let content = UNMutableNotificationContent()
        // Three of four have no name: "a fountain" reads better than "Unnamed fountain".
        if let name = font.name, !name.isEmpty {
            content.title = L10n.t("ios.passingBy.noticeTitle", ["name": name])
        } else {
            content.title = L10n.t("ios.passingBy.noticeTitleUnnamed")
        }
        content.body = L10n.t("ios.passingBy.noticeBody")
        content.sound = .default
        content.categoryIdentifier = Self.category
        content.threadIdentifier = Self.category
        content.userInfo = ["url": "/fonts/\(font.id.uuidString)", "fontID": font.id.uuidString,
                            "fontName": font.name ?? ""]
        let request = UNNotificationRequest(identifier: "passingBy.\(font.id.uuidString)", content: content, trigger: nil)
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            log.error("notice not posted: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func isTravelling() async -> Bool {
        let fix = manager.location.flatMap { Date.now.timeIntervalSince($0.timestamp) <= PassingByRules.freshFix ? $0 : nil }
        let speed = fix.flatMap { $0.speedAccuracy >= 0 && $0.speedAccuracy < 5 ? $0.speed : nil }
        return PassingByRules.isTravelling(motion: await recentMotion(), speed: speed)
    }

    /// The activity of the last few minutes; empty without the chip or the permission.
    private func recentMotion() async -> [MotionSample] {
        guard CMMotionActivityManager.isActivityAvailable(),
              CMMotionActivityManager.authorizationStatus() != .denied,
              CMMotionActivityManager.authorizationStatus() != .restricted else { return [] }
        let now = Date.now
        return await withCheckedContinuation { continuation in
            motion.queryActivityStarting(from: now.addingTimeInterval(-PassingByRules.travelLookBack), to: now,
                                         to: .main) { activities, _ in
                let samples = (activities ?? []).map {
                    MotionSample(at: $0.startDate, automotive: $0.automotive,
                                 onFoot: $0.walking || $0.running || $0.cycling || ($0.stationary && !$0.automotive),
                                 confident: $0.confidence != .low)
                }
                continuation.resume(returning: samples)
            }
        }
    }

    /// The three chips, as buttons on the notice, and "I haven't seen it".
    private static func registerCategory() {
        let chips = [WaterStatus.flowing, .trickle, .dry].map {
            UNNotificationAction(identifier: "passingBy.\($0.rawValue)", title: "\($0.emoji) \(L10n.t($0.labelKey))", options: [])
        }
        let notSeen = UNNotificationAction(identifier: notSeenAction, title: L10n.t("ios.passingBy.notSeen"), options: [])
        let category = UNNotificationCategory(identifier: Self.category, actions: chips + [notSeen], intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    /// A chip pressed on the notice: saved like any quick review, through the outbox, so
    /// it goes out when there is signal. Returns false for "not seen" or anything else.
    @discardableResult
    static func answer(action: String, userInfo: [AnyHashable: Any],
                       outbox: Outbox = .shared, sync: OutboxSync? = .shared) -> Bool {
        guard action.hasPrefix("passingBy."), action != notSeenAction,
              let status = WaterStatus(String(action.dropFirst("passingBy.".count))),
              let id = (userInfo["fontID"] as? String).flatMap(UUID.init(uuidString:)) else { return false }
        let name = (userInfo["fontName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        // Near the fountain by definition: never a remote review.
        let review = NewReview(waterStatus: status.rawValue, confirmIfUnchanged: true, remoteDistanceM: nil)
        outbox.enqueueReview(review, fontID: id, fontName: name)
        sync?.flush(reason: "passingBy")
        return true
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            // The second half of turning it on: "While using" granted, now "Always".
            if self.isEnabled, status == .authorizedWhenInUse { manager.requestAlwaysAuthorization() }
            if self.isEnabled, status == .authorizedAlways, manager.monitoredRegions.isEmpty { await self.refresh() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let last = locations.last
        Task { @MainActor in self.finishLocating(last) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        Task { @MainActor in self.finishLocating(nil) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        let id = region.identifier
        Task { @MainActor in await self.entered(id) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard region.identifier == Self.refreshID else { return }
        Task { @MainActor in await self.refresh() }
    }
}
