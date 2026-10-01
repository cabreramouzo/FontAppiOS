import CoreLocation
import CoreMotion
import Foundation
import Observation
import OSLog
import UIKit
import UserNotifications

/// "You are passing by a fountain: is it flowing?", answered from the notice itself.
///
/// All of it happens on the iPhone: iOS watches a few circles around fountains (region
/// monitoring, cheap on battery, works without signal) and the app posts a **local**
/// notice. The position is never sent to be stored, and no server push is involved:
/// on a mountain there is rarely signal for one to arrive anyway.
///
/// Opt-in from onboarding or Settings: it needs "Always" location and motion permission.
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
    /// Never at night: notices only between 7:00 and 22:00, in minutes since midnight. The
    /// person can narrow this window in Settings, never widen it.
    static let dayStarts = 7 * 60, dayEnds = 22 * 60
    /// The days the person wants notices, as `Calendar` weekdays (1 = Sunday … 7 = Saturday).
    static let allDays: Set<Int> = Set(1...7)
    /// Core Motion reports changes, not a continuous stream. A drive can start long
    /// before a region wakes the app, so look back far enough to find its last change.
    static let travelLookBack: TimeInterval = 2 * 60 * 60
    /// 12.6 km/h is already too fast to stop and check a fountain while passing it.
    static let travellingSpeed: CLLocationSpeed = 3.5
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
    static func shouldNotify(_ fontID: UUID, at place: CLLocationCoordinate2D? = nil,
                             history: [PassingByNotice], now: Date = .now,
                             prefs: PassingByPrefs = .init(), focusMuted: Bool = false,
                             calendar: Calendar = .current) -> Bool {
        if focusMuted || prefs.isPaused(at: now) { return false }
        if !prefs.days.contains(calendar.component(.weekday, from: now)) { return false }
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        if !(max(prefs.from, dayStarts)..<min(prefs.until, dayEnds)).contains(minute) { return false }
        if let place, prefs.quietPlaces.contains(where: { $0.contains(place) }) { return false }
        if history.contains(where: { $0.fontID == fontID && now.timeIntervalSince($0.at) < sameFountainAgain }) {
            return false
        }
        if let last = history.map(\.at).max(), now.timeIntervalSince(last) < betweenNotices { return false }
        let today = history.filter { calendar.isDate($0.at, inSameDayAs: now) }.count
        return today < min(max(prefs.perDay, 1), perDay)
    }
}

/// What the person chose in Settings for the passing-by notices. Everything here can only
/// make the app ask less than the rules allow, never more.
nonisolated struct PassingByPrefs: Codable, Equatable, Sendable {
    var days: Set<Int> = PassingByRules.allDays
    /// The window, in minutes since midnight, inside 7:00–22:00.
    var from = PassingByRules.dayStarts
    var until = PassingByRules.dayEnds
    var perDay = PassingByRules.perDay
    /// Paused until then; `.distantFuture` is "until I resume".
    var pausedUntil: Date?
    var quietPlaces: [QuietPlace] = []

    func isPaused(at now: Date) -> Bool { pausedUntil.map { now < $0 } ?? false }

    static let maxQuietPlaces = 5
}

/// "Not near home": no notice for fountains inside this circle.
nonisolated struct QuietPlace: Codable, Equatable, Identifiable, Sendable {
    static let radius: CLLocationDistance = 300

    var id = UUID()
    var name: String
    var latitude: Double
    var longitude: Double

    func contains(_ point: CLLocationCoordinate2D) -> Bool {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: point.latitude, longitude: point.longitude)) <= Self.radius
    }
}

/// How long "Pause" lasts, from Settings or from Shortcuts.
nonisolated enum PassingByPause: String, CaseIterable, Sendable {
    case day, week, untilResumed

    func until(from now: Date) -> Date {
        switch self {
        case .day: now.addingTimeInterval(86_400)
        case .week: now.addingTimeInterval(7 * 86_400)
        case .untilResumed: .distantFuture
        }
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
    /// A notice requires positive evidence of moving on foot or by bike. A car can be
    /// stationary at traffic lights and a missing background fix cannot prove walking.
    /// Speed takes precedence if it contradicts a lagging activity classification.
    static func canNotify(motion: [MotionSample], speed: CLLocationSpeed?, now: Date = .now) -> Bool {
        if let speed, speed >= travellingSpeed { return false }
        let recent = motion.filter { $0.confident && (0...travelLookBack).contains(now.timeIntervalSince($0.at))
            && ($0.automotive || $0.onFoot) }
        guard let latest = recent.max(by: { $0.at < $1.at }) else { return false }
        return latest.onFoot && !latest.automotive
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
    /// The person's limits: days, hours, how many, pause and places without notices.
    var prefs: PassingByPrefs {
        didSet { defaults.set(try? JSONEncoder().encode(prefs), forKey: Self.prefsKey) }
    }
    private(set) var authorization: CLAuthorizationStatus = .notDetermined

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private let motion = CMMotionActivityManager()
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let log = Logger(subsystem: "net.fontapp.FontApp", category: "passingBy")
    @ObservationIgnored private var locating: [CheckedContinuation<CLLocation?, Never>] = []
    @ObservationIgnored private var locationRequestID: UUID?
    /// The fountains being watched, for the notice's name and position.
    @ObservationIgnored private var watched: [String: FontSummary] = [:]

    private static let enabledKey = "passingBy.enabled"
    private static let prefsKey = "passingBy.prefs"
    /// Set by the Focus filter: a Focus that silences these notices is on.
    static let focusMutedKey = "passingBy.focusMuted"
    private static let historyKey = "passingBy.history"
    private static let watchedKey = "passingBy.watched"
    private static let refreshID = "passingBy.refresh"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Self.enabledKey)
        prefs = defaults.data(forKey: Self.prefsKey)
            .flatMap { try? JSONDecoder().decode(PassingByPrefs.self, from: $0) } ?? PassingByPrefs()
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

    var motionAccessBlocked: Bool {
        CMMotionActivityManager.authorizationStatus() == .denied
            || CMMotionActivityManager.authorizationStatus() == .restricted
    }

    /// Asks Motion & Fitness (the first query is what asks) and waits for the answer.
    /// If refused, uncertain passage events are skipped rather than risking a car alert.
    func askMotion() async {
        guard needsMotionAsk else { return }
        _ = await recentMotion()
    }

    func pause(_ length: PassingByPause) { prefs.pausedUntil = length.until(from: .now) }
    func resume() { prefs.pausedUntil = nil }

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
        await saveCovers(for: chosen)
    }

    // MARK: Covers

    /// The cover of each watched fountain, saved small on the phone while there is
    /// signal: the notice carries it, and on the Watch a photo says which fountain it is
    /// faster than a name (most have none). Near a fountain there is often no signal.
    private static var coversDirectory: URL {
        URL.cachesDirectory.appending(path: "passingBy", directoryHint: .isDirectory)
    }

    private static func coverFile(_ id: UUID) -> URL {
        coversDirectory.appending(path: "\(id.uuidString).jpg")
    }

    private func saveCovers(for chosen: [FontSummary]) async {
        let fm = FileManager.default
        try? fm.createDirectory(at: Self.coversDirectory, withIntermediateDirectories: true)
        let keep = Set(chosen.filter { $0.image != nil }.map { "\($0.id.uuidString).jpg" })
        for name in (try? fm.contentsOfDirectory(atPath: Self.coversDirectory.path())) ?? [] where !keep.contains(name) {
            try? fm.removeItem(at: Self.coversDirectory.appending(path: name))
        }
        for font in chosen {
            let file = Self.coverFile(font.id)
            guard !fm.fileExists(atPath: file.path()), let url = APIClient.shared.imageURL(font.image) else { continue }
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let small = await UIImage(data: data)?.byPreparingThumbnail(ofSize: CGSize(width: 480, height: 480)),
                  let jpeg = small.jpegData(compressionQuality: 0.7) else { continue }
            try? jpeg.write(to: file, options: .atomic)
        }
    }

    /// iOS moves an attachment's file into its own store: a copy goes, the cover stays
    /// for the next time.
    private static func coverAttachment(_ id: UUID) -> UNNotificationAttachment? {
        let file = coverFile(id)
        guard FileManager.default.fileExists(atPath: file.path()) else { return nil }
        let copy = URL.temporaryDirectory.appending(path: "passingBy-\(UUID().uuidString).jpg")
        guard (try? FileManager.default.copyItem(at: file, to: copy)) != nil else { return nil }
        return try? UNNotificationAttachment(identifier: "cover", url: copy, options: nil)
    }

    private func stop() {
        for region in manager.monitoredRegions { manager.stopMonitoring(for: region) }
        try? FileManager.default.removeItem(at: Self.coversDirectory)
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
            if locating.count == 1 {
                let requestID = UUID()
                locationRequestID = requestID
                manager.requestLocation()
                Task {
                    try? await Task.sleep(for: .seconds(8))
                    if locationRequestID == requestID { finishLocating(nil) }
                }
            }
        }
    }

    private func finishLocating(_ location: CLLocation?) {
        locationRequestID = nil
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
        guard PassingByRules.shouldNotify(
            font.id, at: CLLocationCoordinate2D(latitude: font.latitude, longitude: font.longitude),
            history: history, now: Self.clock, prefs: prefs,
            focusMuted: defaults.bool(forKey: Self.focusMutedKey)) else {
            log.info("near \(id, privacy: .public): the rules say not now")
            return
        }
        // Checked after the cheap rules and before noting it: driving past must not use
        // up the fountain's turn for when the person walks by.
        if !(await canNotifyForMovement()) {
            log.info("near \(id, privacy: .public): travel state uncertain or in a vehicle, no notice")
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
        if let cover = Self.coverAttachment(font.id) { content.attachments = [cover] }
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

    private func canNotifyForMovement() async -> Bool {
        // A region event often relaunches the app with no current fix. Ask for one so a
        // stale cached speed cannot make the decision; no fix means no notice.
        let cached = manager.location
        let fix: CLLocation?
        if let cached, abs(Date.now.timeIntervalSince(cached.timestamp)) <= PassingByRules.freshFix {
            fix = cached
        } else {
            fix = await currentLocation()
        }
        guard let fix, abs(Date.now.timeIntervalSince(fix.timestamp)) <= PassingByRules.freshFix else { return false }
        let speed = fix.speed >= 0 && fix.speedAccuracy >= 0 && fix.speedAccuracy < 5 ? fix.speed : nil
        if let speed, speed >= PassingByRules.travellingSpeed { return false }
        return PassingByRules.canNotify(motion: await recentMotion(), speed: speed)
    }

    /// Recent activity changes; empty without the sensor or its permission.
    private func recentMotion() async -> [MotionSample] {
        guard CMMotionActivityManager.isActivityAvailable(),
              CMMotionActivityManager.authorizationStatus() == .authorized else { return [] }
        let now = Date.now
        return await withCheckedContinuation { continuation in
            motion.queryActivityStarting(from: now.addingTimeInterval(-PassingByRules.travelLookBack), to: now,
                                         to: .main) { activities, _ in
                let samples = (activities ?? []).map {
                    MotionSample(at: $0.startDate, automotive: $0.automotive,
                                 onFoot: $0.walking || $0.running || $0.cycling,
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
