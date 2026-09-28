import SwiftUI

@main
struct FontAppApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var location = LocationService()
    @State private var session: SessionStore
    @State private var outbox: Outbox
    @State private var sync: OutboxSync
    @State private var bell = Bell()

    init() {
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
            ContentView()
                .environment(location)
                .environment(session)
                .environment(outbox)
                .environment(OfflineZones.shared)
                .environment(bell)
                .task {
                    await session.refresh()
                    if session.isSignedIn { await bell.reload() }
                }
                .onChange(of: session.userID) { _, userID in
                    outbox.sessionChanged(to: userID)
                    sync.flush(reason: "session")
                    bell.clear()
                    if userID != nil { Task { await bell.reload() } }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                sync.flush(reason: "foreground")
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
