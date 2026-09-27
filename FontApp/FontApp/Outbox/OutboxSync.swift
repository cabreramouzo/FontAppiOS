import BackgroundTasks
import Foundation
import Network
import Observation
import OSLog

/// Decides when the outbox is flushed: when the network comes back, when the app comes
/// to the front, after a sign-in, and in the background.
///
/// The background part is what the web cannot do on iOS (no Background Sync in Safari):
/// a review saved on a mountain goes out when the phone finds signal in the pocket,
/// without opening the app. iOS chooses when the refresh runs, so it is "soon", not
/// "right away"; opening the app still sends at once.
@Observable
final class OutboxSync {
    static let taskIdentifier = "net.fontapp.FontApp.outbox"
    static let shared = OutboxSync()

    private(set) var isOnline = true

    @ObservationIgnored private let outbox: Outbox
    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private let log = Logger(subsystem: "net.fontapp.FontApp", category: "outbox")

    init(outbox: Outbox = .shared) {
        self.outbox = outbox
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.networkChanged(online: online) }
        }
        monitor.start(queue: DispatchQueue(label: "net.fontapp.FontApp.network"))
    }

    private func networkChanged(online: Bool) {
        let cameBack = online && !isOnline
        isOnline = online
        if cameBack { flush(reason: "network") }
    }

    func flush(reason: String) {
        guard !outbox.items.isEmpty else { return }
        log.info("flush: \(reason, privacy: .public)")
        Task { await outbox.flush() }
    }

    /// Asks iOS for a background run while something is pending. Called when the app
    /// goes to the background.
    func scheduleBackgroundFlush() {
        guard !outbox.mine.isEmpty else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 5 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // The simulator refuses background tasks; nothing to do but try in the foreground.
            log.info("background flush not scheduled: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The background run: send, and ask for another one if something is still pending.
    func runInBackground() async {
        await outbox.flush()
        scheduleBackgroundFlush()
    }
}
