import Foundation

/// The sentence to show for a failed request, in the reader's language.
/// Same order as `describeError` in `web/src/lib/apiError.ts`.
nonisolated enum ErrorText {
    static func describe(_ error: any Error, bundle: Bundle = .main) -> String {
        guard let e = error as? APIError else { return L10n.t("error.generic", bundle: bundle) }
        if e.status == 0 { return L10n.t("error.network", bundle: bundle) }
        // The code wins over everything but the network: it says more than the status.
        if e.code == "image.rateLimit", let retry = e.retryAfter {
            return L10n.t("err.image.rateLimit", ["minutes": minutes(retry)], bundle: bundle)
        }
        if let code = e.code, let text = L10n.lookup("err.\(code)", bundle: bundle) { return text }
        // Read limits carry no code: handle every 429 by status.
        if e.status == 429 {
            if let retry = e.retryAfter {
                return L10n.t("error.tooManyRetry", ["minutes": minutes(retry)], bundle: bundle)
            }
            return L10n.t("error.tooMany", bundle: bundle)
        }
        if e.status == 401 { return L10n.t("error.unauthorized", bundle: bundle) }
        // An unknown code: the server's own sentence (Spanish) beats a generic one.
        if let reason = e.reason, !reason.isEmpty { return reason }
        return L10n.t("error.generic", bundle: bundle)
    }

    private static func minutes(_ seconds: TimeInterval) -> Int {
        max(1, Int((seconds / 60).rounded(.up)))
    }
}
