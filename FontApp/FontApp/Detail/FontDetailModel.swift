import CoreLocation
import Foundation
import Observation

/// Loads a fountain with its reviews and reports.
@Observable
final class FontDetailModel {
    enum State {
        case loading
        case loaded(FontDetail)
        /// Only the map's summary could be shown: no signal. The message says why.
        case offline(FontDetail, String)
        case failed(String)
    }

    let fontID: UUID
    private(set) var state: State = .loading
    private(set) var reviews: [CommentResponse] = []
    private(set) var reports: [ReportResponse] = []
    /// The chips, once the fountain (and so its position) is known.
    private(set) var quickReview: QuickReviewModel?
    /// The first photo, for a fountain that has none.
    private(set) var photoUpload: PhotoUploadModel?
    /// A failed "still the same", already translated.
    private(set) var actionError: String?

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let fallback: FontDetail?

    /// `summary` is what the map pin knew; it stands in when the page cannot load.
    init(fontID: UUID, summary: FontSummary? = nil, api: APIClient = .shared) {
        self.fontID = fontID
        self.api = api
        // Opened from a list, not a pin: a saved zone may still know the fountain.
        fallback = (summary ?? OfflineZones.shared.font(fontID)).map(FontDetail.init(summary:))
    }

    /// The fountain on screen, fully loaded or from the summary.
    var font: FontDetail? {
        switch state {
        case .loaded(let font), .offline(let font, _): font
        default: nil
        }
    }

    func load() async {
        if case .failed = state { state = .loading }
        do {
            async let font = api.font(fontID)
            async let reviews = api.comments(of: fontID)
            async let reports = api.reports(of: fontID)
            let loaded = try await (font, reviews, reports)
            self.reviews = loaded.1
            self.reports = Self.threaded(loaded.2)
            state = .loaded(loaded.0)
            prepareContributions(for: loaded.0)
        } catch is CancellationError {
            return
        } catch {
            // A reload that fails (no signal after a contribution was queued) keeps the
            // page on screen: replacing it with an error would hide what is still true.
            if case .loaded = state { return }
            if let fallback, let e = error as? APIError, e.status == 0 {
                state = .offline(fallback, ErrorText.describe(error))
                prepareContributions(for: fallback)
            } else {
                state = .failed(ErrorText.describe(error))
            }
        }
    }

    func didEdit(_ font: FontDetail) {
        state = .loaded(font)
        // Coordinates and name captured by contribution models must follow the edit.
        quickReview = nil
        photoUpload = nil
        prepareContributions(for: font)
    }

    private func prepareContributions(for font: FontDetail) {
        if photoUpload == nil {
            photoUpload = PhotoUploadModel(fontID: fontID, fontName: font.name)
        }
        if quickReview == nil {
            quickReview = QuickReviewModel(fontID: fontID, fontName: font.name,
                                           coordinate: .init(latitude: font.latitude, longitude: font.longitude))
        }
    }

    /// The review "still the same" is offered on: the latest one with a water status, if
    /// someone else wrote it (confirming your own report is refused for a day).
    func confirmable(by userID: UUID?, now: Date = .now) -> CommentResponse? {
        guard let userID, let latest = latestReview, latest.waterStatus != nil else { return nil }
        if latest.userID == userID {
            // Your own report: the server lets you say it again a day after the report and
            // after your last confirmation (`web/src/lib/selfConfirm.ts`); before, a 403.
            let last = [latest.createdAt, latest.lastConfirmedAt].compactMap { $0 }.max() ?? latest.createdAt
            guard now.timeIntervalSince(last) >= 86_400 else { return nil }
        }
        return latest
    }

    /// Your own status report, while it is too recent to say it again: the server refuses
    /// confirming your own report for a day (`confirm.tooSoon`, `web/src/lib/selfConfirm.ts`),
    /// so the chips would only publish a twin — the fountain's creation status included,
    /// which is its first review.
    func ownRecentReport(by userID: UUID?, now: Date = .now) -> CommentResponse? {
        guard let userID, let latest = latestReview, latest.waterStatus != nil,
              latest.userID == userID else { return nil }
        return confirmable(by: userID, now: now) == nil ? latest : nil
    }

    /// The newest review: the current status card. The rest are the history.
    var latestReview: CommentResponse? {
        reviews.max { $0.createdAt != $1.createdAt ? $0.createdAt < $1.createdAt : $0.id.uuidString > $1.id.uuidString }
    }

    /// Everything but the newest, newest first.
    var previousReviews: [CommentResponse] {
        let latestID = latestReview?.id
        return reviews.filter { $0.id != latestID }.sorted { $0.createdAt > $1.createdAt }
    }

    func setStillTheSame(_ review: CommentResponse, _ on: Bool) async {
        actionError = nil
        do {
            _ = try await api.confirm(review.id, on: fontID, on)
            NotificationCenter.default.post(name: .fontChanged, object: fontID)
            await load()
        } catch {
            actionError = ErrorText.describe(error)
        }
    }

    /// Newest threads first, each reply right under the report it answers.
    static func threaded(_ reports: [ReportResponse]) -> [ReportResponse] {
        let ids = Set(reports.map(\.id))
        let roots = reports.filter { $0.parentID == nil || !ids.contains($0.parentID!) }
            .sorted { $0.createdAt > $1.createdAt }
        let replies = Dictionary(grouping: reports.filter { $0.parentID.map(ids.contains) ?? false }) { $0.parentID! }
        func thread(_ report: ReportResponse) -> [ReportResponse] {
            [report] + (replies[report.id] ?? []).sorted { $0.createdAt < $1.createdAt }.flatMap(thread)
        }
        return roots.flatMap(thread)
    }

    /// Built from the full list of reviews, as the web's detail page does. The
    /// server's summary is the fallback for a fountain whose reviews list is empty.
    func evidence(for font: FontDetail, now: Date = .now) -> ConfidenceEvidence {
        let fromReviews = Confidence.evidence(from: reviews, now: now)
        if fromReviews.lastWaterStatus != nil { return fromReviews }
        return ConfidenceEvidence(lastWaterStatus: font.lastWaterStatus, lastUpdate: font.lastUpdate,
                                  recentStatusConflict: font.statusConflict ?? false)
    }
}
