import SwiftUI

/// The badges earned **at this fountain**: who took each, and which are still free.
/// Port of `web/src/components/FontBadges.tsx`, whose comments hold the reasoning. Not
/// the whole collection: "International" says nothing about this fountain. The free ones
/// are the interesting half — "it has no photo yet" is a concrete task, ten metres away.
struct FontBadgesSection: View {
    let creatorName: String?
    let creatorTier: String?
    /// Pioneer is only earned on imported fountains (no creator): offering a prize the
    /// server will not give is worse than offering none.
    let pioneerCounts: Bool
    let pioneerName: String?
    let hasPhoto: Bool
    let photoAuthor: String?
    /// Days since anyone checked it; nil when nobody ever did.
    let daysSinceCheck: Int?

    /// The same 91 days from which the freshness curve pays "sentinel".
    static let dormantDays = 91

    private struct Row: Identifiable {
        let family: String
        let earned: Bool
        let by: String?
        let tier: String?
        let hint: String?
        var id: String { family }
    }

    private var rows: [Row] {
        var rows = [creatorName.map { Row(family: "discoverer", earned: true, by: $0, tier: creatorTier, hint: nil) }
                    ?? Row(family: "discoverer", earned: false, by: nil, tier: nil, hint: L10n.t("detail.badges.imported"))]
        if pioneerCounts {
            rows.append(pioneerName.map { Row(family: "pioneer", earned: true, by: $0, tier: nil, hint: nil) }
                        ?? Row(family: "pioneer", earned: false, by: nil, tier: nil, hint: L10n.t("detail.badges.noReview")))
        }
        // Earned without a known author when the photo came by an edit: in colour, no name.
        rows.append(hasPhoto
            ? Row(family: "firstLight", earned: true, by: photoAuthor, tier: nil,
                  hint: photoAuthor == nil ? L10n.t("detail.badges.unknownAuthor") : nil)
            : Row(family: "firstLight", earned: false, by: nil, tier: nil, hint: L10n.t("detail.badges.noPhoto")))
        // Sentinel only when it is at stake: who woke it in the past cannot be told here.
        if let days = daysSinceCheck, days >= Self.dormantDays {
            rows.append(Row(family: "sentinel", earned: false, by: nil, tier: nil,
                            hint: L10n.t("detail.badges.stale", ["n": days])))
        }
        return rows
    }

    var body: some View {
        Section {
            ForEach(rows) { row in
                HStack(spacing: 12) {
                    BadgeImage(family: row.family, tier: row.tier, locked: !row.earned, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t("game.badge.\(row.family)"))
                            .font(.body.weight(.semibold))
                            .foregroundStyle(row.earned ? .primary : .secondary)
                        Group {
                            if let by = row.by {
                                HStack(spacing: 4) { Text(L10n.t("detail.badges.by")); UserLink(username: by) }
                            } else if let hint = row.hint {
                                Text(hint)
                            }
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
            }
        } header: {
            Text(L10n.t("detail.badges.title"))
        } footer: {
            Text(L10n.t("detail.badges.intro"))
        }
    }
}
