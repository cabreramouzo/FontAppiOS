import SwiftUI
import UIKit

extension Color {
    /// The web's "warning" orange (MUI): `#ed6c02` on light, `#ffa726` on dark. The colour
    /// this app uses for "this is not resolved" — something waiting to be sent.
    static let warning = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1.0, green: 0.655, blue: 0.149, alpha: 1)
            : UIColor(red: 0.929, green: 0.424, blue: 0.008, alpha: 1)
    })

    /// Text on a filled `warning`: white on the light orange, near-black on the dark one.
    static let onWarning = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 0, alpha: 0.87) : .white
    })
}

/// What the notice on the map says about the queue, and never more than is true.
///
/// Same states as the web's `PendingUploads.tsx` (rule R5.6 in `FontAppBE/docs/client-rules.md`).
nonisolated struct ConnectivityNotice: Equatable, Sendable {
    /// What the person still has to care about is orange; what only informs is neutral.
    enum Tone: Equatable, Sendable { case neutral, warning, success, progress }

    let tone: Tone
    let titleKey: String
    let titleCount: Int?
    let detailKey: String
    let detailCount: Int?

    var title: String { L10n.t(titleKey, titleCount.map { ["n": $0] } ?? [:]) }
    var detail: String { L10n.t(detailKey, detailCount.map { ["n": $0] } ?? [:]) }

    /// The queue as the notice sees it.
    struct Input: Equatable, Sendable {
        var online: Bool
        var pending: Int
        /// Saved by another account than the one signed in.
        var others: Int
        var needsAuth: Bool
        var sending: Bool
        /// A flush already ran and something is still pending.
        var tried: Bool
        /// Everything went out a moment ago.
        var justSynced: Bool
    }

    /// `nil` when there is nothing to say: online, nothing pending, nothing just sent.
    static func make(_ i: Input) -> ConnectivityNotice? {
        if i.pending == 0, !i.justSynced, i.online { return nil }

        if !i.online {
            return i.pending > 0
                ? ConnectivityNotice(tone: .warning, titleKey: "offline.offlinePending", titleCount: i.pending,
                                     detailKey: "offline.savedSafe", detailCount: nil)
                : ConnectivityNotice(tone: .neutral, titleKey: "offline.banner", titleCount: nil,
                                     detailKey: "offline.connectionHint", detailCount: nil)
        }
        if i.pending == 0 {
            return ConnectivityNotice(tone: .success, titleKey: "offline.synced", titleCount: nil,
                                      detailKey: "offline.syncedHint", detailCount: nil)
        }
        return ConnectivityNotice(tone: i.sending ? .progress : .warning,
                                  titleKey: i.sending ? "offline.syncing" : "offline.pending", titleCount: i.pending,
                                  detailKey: pendingDetail(i), detailCount: i.others > 0 ? i.others : nil)
    }

    /// Online with something pending: which of the problems it is.
    private static func pendingDetail(_ i: Input) -> String {
        if i.others > 0 { return "offline.otherAccount" }
        if i.needsAuth { return "offline.needsLogin" }
        return i.tried ? "offline.retryHint" : "offline.pendingHint"
    }

    /// Whether the card may shrink to a chip: not while sending nor during the "synced"
    /// confirmation — both go away on their own — and never when there is no notice.
    static func mayShrink(_ i: Input) -> Bool {
        !(i.sending || i.justSynced) && !(i.online && i.pending == 0)
    }

    /// How long the card stays whole before it becomes a chip. The chip carries the same
    /// label, so nothing is hidden, and the card returns whenever something changes.
    static let shrinkAfter: Duration = .seconds(3)
    /// How long "all synced" stays.
    static let syncedFor: Duration = .seconds(4)
}
