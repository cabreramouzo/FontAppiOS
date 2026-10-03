import SwiftUI
import TipKit

@main
struct FontAppApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var location = LocationService()
    @State private var session: SessionStore
    @State private var outbox: Outbox
    @State private var sync: OutboxSync
    @State private var bell = Bell()
    @State private var favorites = Favorites()
    @State private var celebrations = BadgeCelebrations()
    @State private var showsWelcome: Bool

    init() {
        // Decide before the stores below create files on a genuinely fresh install.
        _showsWelcome = State(initialValue: WelcomeGate.shouldPresent())
        // Before the first map: how much of the map seen is kept for not downloading it again.
        MapTileCache.configure()
        AppTips.configure()
        let session = SessionStore()
        let outbox = Outbox.shared
        // Before anything is sent, the outbox has to know whose it is.
        outbox.currentUserID = session.userID
        _session = State(initialValue: session)
        _outbox = State(initialValue: outbox)
        _sync = State(initialValue: OutboxSync.shared)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(showsWelcome: $showsWelcome)
                .environment(location)
                .environment(session)
                .environment(outbox)
                .environment(OfflineZones.shared)
                .environment(bell)
                .environment(favorites)
                // A badge or a level you did not have: over everything, with confetti.
                .overlay {
                    if let novelty = celebrations.current {
                        BadgeCelebrationView(novelty: novelty) { withAnimation { celebrations.dismiss() } }
                            .environment(session)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: celebrations.current)
                // Right after contributing is when it matters: the fountain is still there.
                .onReceive(NotificationCenter.default.publisher(for: .fontChanged)) { _ in
                    celebrations.contributed(session.userID)
                }
                .task {
                    PushNotifications.shared.sessionChanged(to: session.userID)
                    await PushNotifications.shared.refresh()
                    favorites.sessionChanged(to: session.userID)
                    await session.refresh()
                    celebrations.checkAtLaunch(session.userID)
                    if session.isSignedIn {
                        async let inbox: Void = bell.reload()
                        async let starred: Void = favorites.reload()
                        _ = await (inbox, starred)
                    }
                }
                .onChange(of: session.userID) { _, userID in
                    PushNotifications.shared.sessionChanged(to: userID)
                    if userID == nil { PassingBy.shared.signedOut() }
                    outbox.sessionChanged(to: userID)
                    sync.flush(reason: "session")
                    bell.clear()
                    favorites.sessionChanged(to: userID)
                    if userID != nil { Task { await bell.reload(); await favorites.reload() } }
                    celebrations.checkAtLaunch(userID)
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                sync.flush(reason: "foreground")
                MapHelpTip.appOpened.sendDonation()
                Task { await PushNotifications.shared.refresh() }
                // Opening the app somewhere new: watch the fountains around here.
                Task { await PassingBy.shared.refresh() }
                celebrations.checkAtLaunch(session.userID)
                if session.isSignedIn { Task { await bell.reload() } }
            case .background: sync.scheduleBackgroundFlush()
            default: break
            }
        }
        .backgroundTask(.appRefresh(OutboxSync.taskIdentifier)) {
            await OutboxSync.shared.runInBackground()
        }
    }
}
