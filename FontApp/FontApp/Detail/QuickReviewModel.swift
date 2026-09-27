import CoreLocation
import Foundation
import Observation

extension Notification.Name {
    /// A contribution changed a fountain (object: its `UUID`). The map reloads its pins.
    static let fontChanged = Notification.Name("FontAppFontChanged")
}

/// The three chips: flowing, trickle, dry. Never `unknown` (says nothing from someone in
/// front of the fountain) nor `gone` (two of them retire a fountain; too costly for one tap).
@Observable
final class QuickReviewModel {
    static let chips: [WaterStatus] = [.flowing, .trickle, .dry]
    /// Long enough to notice a wrong tap, short enough not to linger. Same as the web.
    static let undoWindow: TimeInterval = 10

    enum State: Equatable {
        case idle
        case sending(WaterStatus)
        /// Published (or counted as "still the same"); can be undone until `undoUntil`.
        case sent(CommentResponse.ID, confirmedInstead: Bool, undoUntil: Date)
        case undone
        case failed(String)
    }

    /// Asked before sending when the position says the person is clearly far.
    struct RemoteQuestion: Identifiable {
        let status: WaterStatus
        let meters: Int
        var id: Int { meters }
    }

    let fontID: UUID
    let coordinate: CLLocationCoordinate2D
    private(set) var state: State = .idle
    var remoteQuestion: RemoteQuestion?

    /// Fountains whose remote question was answered in this run: asked once per fountain.
    private static var remoteConfirmed = Set<UUID>()

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private var expiry: Task<Void, Never>?

    init(fontID: UUID, coordinate: CLLocationCoordinate2D, api: APIClient = .shared) {
        self.fontID = fontID
        self.coordinate = coordinate
        self.api = api
    }

    /// True during the undo window after a review lands. Stored, not derived from the
    /// clock, so the button goes away on its own when the window closes.
    private(set) var canUndo = false

    /// The chip was tapped. `fix` is only passed when location permission is granted.
    func tap(_ status: WaterStatus, fix: CLLocation?) async -> Bool {
        if case .sending = state { return false }
        let meters = RemoteReview.distance(from: fix, to: coordinate)
        if let meters, !Self.remoteConfirmed.contains(fontID) {
            remoteQuestion = RemoteQuestion(status: status, meters: meters)
            return false
        }
        return await send(status, remoteDistanceM: meters)
    }

    /// "Yes, I saw it recently."
    func confirmRemote(_ question: RemoteQuestion) async -> Bool {
        Self.remoteConfirmed.insert(fontID)
        remoteQuestion = nil
        return await send(question.status, remoteDistanceM: question.meters)
    }

    private func send(_ status: WaterStatus, remoteDistanceM: Int?) async -> Bool {
        state = .sending(status)
        do {
            let review = NewReview(waterStatus: status.rawValue, confirmIfUnchanged: true,
                                   remoteDistanceM: remoteDistanceM)
            let response = try await api.postReview(on: fontID, review)
            let until = Date.now.addingTimeInterval(Self.undoWindow)
            state = .sent(response.id, confirmedInstead: response.confirmedInstead ?? false, undoUntil: until)
            canUndo = true
            scheduleExpiry(at: until)
            NotificationCenter.default.post(name: .fontChanged, object: fontID)
            return true
        } catch {
            state = .failed(ErrorText.describe(error))
            return false
        }
    }

    /// Deletes the review, or takes the "still the same" back if that is what it became.
    func undo() async -> Bool {
        guard canUndo, case .sent(let id, let confirmedInstead, let until) = state, until > .now else { return false }
        expiry?.cancel()
        canUndo = false
        do {
            if confirmedInstead {
                _ = try await api.confirm(id, on: fontID, false)
            } else {
                try await api.deleteReview(id, on: fontID)
            }
            state = .undone
            NotificationCenter.default.post(name: .fontChanged, object: fontID)
            return true
        } catch {
            state = .failed(ErrorText.describe(error))
            return false
        }
    }

    /// The thanks stays; only the undo button goes when the window closes.
    private func scheduleExpiry(at date: Date) {
        expiry?.cancel()
        expiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, date.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            self?.canUndo = false
        }
    }
}
