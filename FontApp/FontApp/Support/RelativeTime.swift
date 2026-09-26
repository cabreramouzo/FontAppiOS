import Foundation

/// "3 h ago", "yesterday"… with the web's wording (`timeAgo` in `web/src/lib/time.ts`).
nonisolated enum RelativeTime {
    static func string(since date: Date, now: Date = .now, bundle: Bundle = .main) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 60 { return L10n.t("time.moment", bundle: bundle) }
        let minutes = seconds / 60
        if minutes < 60 { return L10n.t("time.min", ["n": minutes], bundle: bundle) }
        let hours = minutes / 60
        if hours < 24 { return L10n.t("time.hour", ["n": hours], bundle: bundle) }
        let days = hours / 24
        if days == 1 { return L10n.t("time.yesterday", bundle: bundle) }
        if days < 30 { return L10n.t("time.days", ["n": days], bundle: bundle) }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}
