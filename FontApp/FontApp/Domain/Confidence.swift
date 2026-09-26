import Foundation

/// How much backing the published water status has. A category, not a score, and it
/// says nothing about whether the fountain is good. Mirrors `web/src/lib/confidence.ts`.
nonisolated enum ConfidenceLevel: String, Sendable, CaseIterable {
    case verified, recent, disputed, stale, unverified

    var labelKey: String { "confidence.\(rawValue)" }
    var detailKey: String { "confidence.\(rawValue)Detail" }

    var emoji: String {
        switch self {
        case .verified: "✅"
        case .recent: "🕐"
        case .disputed: "⚖️"
        case .stale: "⌛"
        case .unverified: "○"
        }
    }
}

nonisolated struct ConfidenceEvidence: Equatable, Sendable {
    var lastWaterStatus: String?
    var lastUpdate: Date?
    var latestConfirmations = 0
    var recentStatusReporters = 0
    var recentStatusConflict = false
}

nonisolated enum Confidence {
    static let freshDays = 30
    private static let day: TimeInterval = 86_400

    static func level(of e: ConfidenceEvidence, now: Date = .now) -> ConfidenceLevel {
        // "Conflicting" beats the last status: a recent "dry" against a recent "flowing"
        // is not settled by whichever came last.
        if e.recentStatusConflict { return .disputed }
        guard e.lastWaterStatus != nil, let lastUpdate = e.lastUpdate else { return .unverified }
        let days = Int((now.timeIntervalSince(lastUpdate) / day).rounded(.down))
        if days > freshDays { return .stale }
        if e.latestConfirmations > 0 || e.recentStatusReporters > 1 { return .verified }
        return .recent
    }

    /// The same evidence built from the full list of reviews, as the detail page has it.
    static func evidence(from reviews: [CommentResponse], now: Date = .now) -> ConfidenceEvidence {
        let withStatus = reviews.filter { $0.waterStatus != nil }.sorted { $0.createdAt > $1.createdAt }
        guard let latest = withStatus.first else { return ConfidenceEvidence() }
        let recent = withStatus.filter {
            now.timeIntervalSince($0.createdAt) <= Double(freshDays) * day && $0.waterStatus != "unknown"
        }
        let families = Set(recent.compactMap { family(of: $0.waterStatus) })
        return ConfidenceEvidence(
            lastWaterStatus: latest.waterStatus,
            lastUpdate: latest.lastConfirmedAt ?? latest.createdAt,
            latestConfirmations: latest.confirmations ?? 0,
            recentStatusReporters: Set(recent.compactMap(\.userID)).count,
            recentStatusConflict: families.count > 1
        )
    }

    private static func family(of status: String?) -> String? {
        switch status {
        case "flowing", "trickle": "water"
        case "dry", "broken", "gone": "unavailable"
        default: nil
        }
    }
}
