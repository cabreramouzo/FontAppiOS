import Foundation

/// The words for a bell notice, as `NotificationBell.tsx` writes them.
///
/// The server sends codes and figures rather than sentences, because it does not know the
/// reader's language. An unknown code falls back to a generic text instead of showing a
/// raw one: old notices stay in the inbox after the server starts sending new codes.
nonisolated enum NotificationText {
    static func title(_ n: NotificationItem, bundle: Bundle = .main) -> String {
        let font = L10n.fontName(n.fontName, bundle: bundle)
        return switch n.kind {
        case "staleGuarded": L10n.t("notif.staleGuarded", ["n": figures(n.excerpt).0], bundle: bundle)
        case "sourceLimit": L10n.t("notif.sourceLimit", bundle: bundle)
        case "userOnFire": L10n.t("notif.onFire", ["user": n.actorName], bundle: bundle)
        case "fontUpdate": L10n.t("notif.fontUpdate", ["font": font], bundle: bundle)
        case "commentLike": L10n.t("notif.commentLike", ["user": n.actorName], bundle: bundle)
        case "mayorTaken": L10n.t("notif.mayorTaken", ["user": n.actorName], bundle: bundle)
        case "reviewConfirmed": L10n.t("notif.reviewConfirmed", ["user": n.actorName], bundle: bundle)
        default: L10n.t("notif.mentionedYou", ["user": n.actorName, "font": font], bundle: bundle)
        }
    }

    /// What caused it. Without this line you would have to open the fountain to know
    /// whether it matters, and it rarely does.
    static func body(_ n: NotificationItem, bundle: Bundle = .main) -> String {
        let font = L10n.fontName(n.fontName, bundle: bundle)
        return switch n.kind {
        case "staleGuarded": L10n.t("notif.staleGuardedBody", ["font": font, "d": figures(n.excerpt).2], bundle: bundle)
        case "sourceLimit": L10n.t("notif.sourceLimitBody", ["hasta": until(n.excerpt)], bundle: bundle)
        case "userOnFire": L10n.t("notif.onFireBody", ["n": n.excerpt], bundle: bundle)
        case "fontUpdate": whatHappened(n.excerpt, who: n.actorName, bundle: bundle)
        case "mayorTaken": L10n.t("notif.mayorTakenBody", ["font": font], bundle: bundle)
        case "reviewConfirmed": L10n.t("notif.reviewConfirmedBody", ["font": font], bundle: bundle)
        default: n.excerpt
        }
    }

    static func systemImage(_ kind: String) -> String {
        switch kind {
        case "staleGuarded": "clock.badge.exclamationmark"
        case "sourceLimit": "plus.circle"
        case "userOnFire": "flame"
        case "fontUpdate": "drop"
        case "commentLike": "heart"
        case "mayorTaken": "crown"
        case "reviewConfirmed": "checkmark.seal"
        default: "at"
        }
    }

    /// `review:dry`, `recovered`, `report`, `resolved`, `hidden:retired`…
    private static func whatHappened(_ excerpt: String, who: String, bundle: Bundle) -> String {
        let parts = excerpt.split(separator: ":", maxSplits: 1).map(String.init)
        let detail = parts.count > 1 ? parts[1] : nil
        switch parts.first {
        case "review":
            if let detail, let status = L10n.lookup("status.\(detail)", bundle: bundle) {
                return L10n.t("notif.fontUpdate.reviewWithStatus", ["user": who, "status": status], bundle: bundle)
            }
            return L10n.t("notif.fontUpdate.review", ["user": who], bundle: bundle)
        case "recovered": return L10n.t("maintenance.recovered", ["user": who], bundle: bundle)
        case "report": return L10n.t("notif.fontUpdate.report", ["user": who], bundle: bundle)
        case "resolved": return L10n.t("notif.fontUpdate.resolved", bundle: bundle)
        case "hidden":
            return L10n.t(detail == "retired" ? "notif.fontUpdate.retired" : "notif.fontUpdate.duplicate", bundle: bundle)
        default: return L10n.t("notif.fontUpdate.other", bundle: bundle)
        }
    }

    /// "7|6|142": forgotten fountains, of how many, days since the oldest was checked.
    /// An unexpected format reads 0 and the notice stays legible.
    static func figures(_ excerpt: String) -> (Int, Int, Int) {
        let n = excerpt.split(separator: "|", omittingEmptySubsequences: false).map { Int($0) ?? 0 }
        return (n.count > 0 ? n[0] : 0, n.count > 1 ? n[1] : 0, n.count > 2 ? n[2] : 0)
    }

    /// The server sends the limit's end as an ISO instant, not a phrase: it is in UTC and
    /// people here span six time zones. The phone knows which one is theirs.
    private static func until(_ excerpt: String) -> String {
        guard let date = try? Date(excerpt, strategy: .iso8601) else { return "" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
