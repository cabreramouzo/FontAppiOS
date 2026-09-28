import Foundation
import Observation

/// The in-app bell: notices that do not deserve a system notification (likes, "still the
/// same" on your review, levels, mentions while you are around) and the history of all.
///
/// It asks at launch, on sign-in and when the app comes back to the foreground, never on
/// a timer: none of this is urgent, and seeing it the next time you look is enough.
@Observable
final class Bell {
    enum State: Equatable { case idle, loading, loaded, failed(String) }

    private(set) var items: [NotificationItem] = []
    private(set) var unread = 0
    private(set) var state: State = .idle

    @ObservationIgnored private let api: APIClient
    /// A reload that started for an account that has since signed out must not land.
    @ObservationIgnored private var generation = 0

    init(api: APIClient = .shared) {
        self.api = api
    }

    func reload() async {
        let requestGeneration = generation
        if items.isEmpty { state = .loading }
        do {
            let inbox = try await api.notifications()
            guard requestGeneration == generation else { return }
            items = inbox.items
            unread = inbox.unread
            state = .loaded
        } catch {
            guard requestGeneration == generation, !(error is CancellationError) else { return }
            // Without signal the last inbox stays: it is still true.
            state = .failed(ErrorText.describe(error))
        }
    }

    /// Opening the bell reads everything. Marked here and not when loading, or any launch
    /// would empty the bell before it was looked at. The rows keep their "new" look until
    /// the next load, so you can still tell which ones they were.
    func opened() async {
        guard unread > 0 else { return }
        let before = unread
        unread = 0
        do {
            try await api.markNotificationsRead()
        } catch {
            unread = before
        }
    }

    /// Signed out: someone else's inbox must not stay on the phone.
    func clear() {
        generation += 1
        items = []
        unread = 0
        state = .idle
    }
}
