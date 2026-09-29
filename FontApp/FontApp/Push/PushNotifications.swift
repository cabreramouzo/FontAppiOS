import Observation
import SwiftUI
import UIKit
import UserNotifications

/// System notifications through APNs. What they are about is the server's decision and
/// the product rule (`FontAppBE/CLAUDE.md`): only what can change what you are about to
/// do — a fountain you follow went dry, an incident, someone talking to you. Everything
/// else goes to the bell. An app gets muted once and never unmuted.
///
/// So permission is **never asked at launch**: only right after something that makes a
/// notice worth having (following a fountain, writing to someone), once.
@Observable
final class PushNotifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = PushNotifications()

    private(set) var status: UNAuthorizationStatus = .notDetermined
    /// The hex token iOS gave this installation.
    private(set) var token: String?
    /// A notice tapped: the web path it points to, for the app to open.
    var opened: URL?

    @ObservationIgnored private var registeredFor: UUID?
    @ObservationIgnored private var userID: UUID?

    /// Installed from Xcode, the token only works on Apple's sandbox server.
    private static var sandbox: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    /// At launch and on returning: the permission may have changed in Settings. With it
    /// granted, the token is asked for again (iOS may rotate it).
    func refresh() async {
        status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        if status == .authorized || status == .provisional {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    /// From Settings: the person asked for it, so it is asked now.
    func enable() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        await refresh()
    }

    /// After following a fountain or writing to someone. Asks only the first time.
    func askIfUseful() {
        guard status == .notDetermined else { return }
        Task {
            let granted = (try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            await refresh()
            if granted { UIApplication.shared.registerForRemoteNotifications() }
        }
    }

    /// The account in use: the token goes to the server under it.
    func sessionChanged(to userID: UUID?) {
        self.userID = userID
        Task { await upload() }
    }

    func didRegister(_ deviceToken: Data) {
        token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { await upload() }
    }

    /// Before signing out, while the token still authenticates.
    func signingOut() async {
        guard let token, registeredFor != nil else { return }
        try? await APIClient.shared.removePushToken(token)
        registeredFor = nil
    }

    private func upload() async {
        guard let token, let userID, registeredFor != userID else { return }
        do {
            try await APIClient.shared.registerPushToken(token, sandbox: Self.sandbox)
            registeredFor = userID
        } catch {
            // Without signal: the next launch or return tries again.
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    /// In the app, the notice still shows as a banner: it is about a fountain you care about.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification)
        async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        // A chip pressed on a "passing by" notice: saved without opening the app.
        let action = response.actionIdentifier
        if action != UNNotificationDefaultActionIdentifier {
            let info = response.notification.request.content.userInfo
            let data = (try? JSONSerialization.data(withJSONObject: info)) ?? Data()
            await MainActor.run {
                let userInfo = (try? JSONSerialization.jsonObject(with: data) as? [AnyHashable: Any]) ?? [:]
                PassingBy.answer(action: action, userInfo: userInfo)
            }
            return
        }
        let path = response.notification.request.content.userInfo["url"] as? String
        await MainActor.run {
            self.opened = path.flatMap { URL(string: $0, relativeTo: URL(string: "https://fontapp.net")) }?.absoluteURL
        }
    }
}

/// UIKit's half: only it receives the device token.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        _ = PushNotifications.shared   // the delegate must be set before a tapped notice arrives
        _ = PassingBy.shared           // and the location one before a region event does
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushNotifications.shared.didRegister(deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {}
}

/// A fontapp.net path the app can show: from a universal link or a tapped notice.
nonisolated enum DeepLink: Equatable, Identifiable {
    case fountain(UUID)
    case profile(String)

    var id: String {
        switch self {
        case .fountain(let id): "f-\(id)"
        case .profile(let handle): "u-\(handle)"
        }
    }

    init?(_ url: URL) {
        guard url.scheme == "https" || url.scheme == "http" else { return nil }
        if let host = url.host(), !(host == "fontapp.net" || host.hasSuffix(".fontapp.net")) { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2 else { return nil }
        switch parts[0] {
        case "fonts": guard let id = UUID(uuidString: parts[1]) else { return nil }; self = .fountain(id)
        case "users": self = .profile(parts[1])
        default: return nil
        }
    }
}
