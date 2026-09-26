import Foundation
import Observation

/// Loads a fountain with its reviews and reports.
@Observable
final class FontDetailModel {
    enum State {
        case loading
        case loaded(FontDetail)
        case failed(String)
    }

    let fontID: UUID
    private(set) var state: State = .loading
    private(set) var reviews: [CommentResponse] = []
    private(set) var reports: [ReportResponse] = []

    @ObservationIgnored private let api: APIClient

    init(fontID: UUID, api: APIClient = .shared) {
        self.fontID = fontID
        self.api = api
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
        } catch is CancellationError {
            return
        } catch {
            state = .failed(ErrorText.describe(error))
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
