import SwiftUI

/// The notice on the map about what is waiting to be sent and whether there is signal.
///
/// It is a card that, after `ConnectivityNotice.shrinkAfter`, becomes a small chip with the
/// same label — **also with things pending**: the queue can take hours, or never empty if
/// what waits is another account's, and a card pinned over the map covers a third of it.
/// The card comes back whenever something changes (signal lost or back, the number
/// pending, the session expiring), and tapping the chip opens it for a while again.
/// Rules R5.6–R5.8 in `FontAppBE/docs/client-rules.md`.
struct ConnectivityNoticeView: View {
    @Environment(Outbox.self) private var outbox
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let sync = OutboxSync.shared
    /// Signed out (or the session expired) with something pending: sending needs an account.
    let onSignIn: () -> Void

    @State private var shrunk = false
    /// Changes when the chip is tapped, to start the timer again.
    @State private var expandedAt = 0
    @State private var justSynced = false
    @State private var showsDetails = false
    @State private var confirmsDiscard = false

    private var input: ConnectivityNotice.Input {
        ConnectivityNotice.Input(online: sync.isOnline, pending: outbox.items.count, others: outbox.othersCount,
                                 needsAuth: outbox.needsAuth || outbox.currentUserID == nil,
                                 sending: outbox.isFlushing, tried: outbox.flushTried, justSynced: justSynced)
    }

    /// Everything that is news: when it changes, the card shows whole again.
    private struct Trigger: Equatable {
        let input: ConnectivityNotice.Input
        let expandedAt: Int
    }

    var body: some View {
        let input = input
        Group {
            if let notice = ConnectivityNotice.make(input) {
                if shrunk && ConnectivityNotice.mayShrink(input) {
                    chip(notice)
                        .transition(.scale(scale: 0.8, anchor: .leading).combined(with: .opacity))
                } else {
                    card(notice, input)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        // Outside the card and the chip: it opens from either, and neither owns it.
        .sheet(isPresented: $showsDetails) { PendingDetailsSheet() }
        // Destructive — the data exist only on this phone — so it asks first, and says how many.
        .confirmationDialog(L10n.t("offline.discardConfirm", ["n": outbox.discardPlan?.count ?? 0]),
                            isPresented: $confirmsDiscard, titleVisibility: .visible) {
            Button(L10n.t("offline.discard"), role: .destructive) {
                outbox.discard(onlyOthers: outbox.discardPlan?.onlyOthers ?? false)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: shrunk)
        .onChange(of: outbox.isFlushing) { was, now in
            if was, !now, outbox.lastSent > 0 { justSynced = true }
        }
        .task(id: justSynced) {
            guard justSynced else { return }
            try? await Task.sleep(for: ConnectivityNotice.syncedFor)
            if !Task.isCancelled { justSynced = false }
        }
        .task(id: Trigger(input: input, expandedAt: expandedAt)) {
            shrunk = false
            guard ConnectivityNotice.mayShrink(input) else { return }
            try? await Task.sleep(for: ConnectivityNotice.shrinkAfter)
            if !Task.isCancelled { shrunk = true }
        }
    }

    // MARK: Shrunk

    /// The same label as the card's title, so shrinking hides nothing. Orange when
    /// something is pending; neutral when it only says there is no signal.
    private func chip(_ notice: ConnectivityNotice) -> some View {
        let pending = notice.tone == .warning
        return Button {
            expandedAt += 1
        } label: {
            Label(notice.title, systemImage: pending ? "exclamationmark.arrow.triangle.2.circlepath" : "icloud.slash")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(pending ? Color.onWarning : Color.primary)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(pending ? AnyShapeStyle(Color.warning) : AnyShapeStyle(.regularMaterial), in: Capsule())
                .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityHint(notice.detail)
    }

    // MARK: Whole

    private func card(_ notice: ConnectivityNotice, _ input: ConnectivityNotice.Input) -> some View {
        HStack(alignment: .center, spacing: 12) {
            icon(notice.tone)
            VStack(alignment: .leading, spacing: 2) {
                Text(notice.title).font(.subheadline.weight(.semibold))
                Text(notice.detail).font(.caption).foregroundStyle(.secondary)
                // See, copy or keep what is stuck: so it is never trapped where nobody can read it.
                if input.pending > 0 {
                    Button(L10n.t("offline.seeDetails")) { showsDetails = true }
                        .font(.caption.weight(.semibold))
                        .frame(minHeight: 44, alignment: .leading)
                }
                // The way out for what can never go (another account's, already published by
                // hand): small text, not a button — the exit must exist, not invite.
                if outbox.discardPlan != nil {
                    Button(L10n.t("offline.discard"), role: .destructive) { confirmsDiscard = true }
                        .font(.caption)
                        .frame(minHeight: 44, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            action(input)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(border(notice.tone), lineWidth: 1))
        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        .accessibilityElement(children: .contain)
    }

    private func border(_ tone: ConnectivityNotice.Tone) -> Color {
        tone == .warning ? Color.warning.opacity(0.6) : Color.secondary.opacity(0.25)
    }

    @ViewBuilder private func icon(_ tone: ConnectivityNotice.Tone) -> some View {
        switch tone {
        case .neutral: Image(systemName: "icloud.slash").foregroundStyle(.secondary)
        case .warning: Image(systemName: "exclamationmark.arrow.triangle.2.circlepath").foregroundStyle(Color.warning)
        case .success: Image(systemName: "checkmark.icloud").foregroundStyle(.green)
        case .progress: ProgressView()
        }
    }

    /// Sign in when nothing can go until there is a session; otherwise send now, unless
    /// every pending item is another account's (there is nothing it could do: offering it
    /// would be a button that is pressed and nothing happens).
    @ViewBuilder private func action(_ input: ConnectivityNotice.Input) -> some View {
        if input.online, input.pending > 0 {
            if input.needsAuth {
                Button(L10n.t("nav.enter"), action: onSignIn)
                    .buttonStyle(.borderedProminent).tint(Color.warning)
                    .frame(minHeight: 44)
            } else if input.others < input.pending {
                Button(L10n.t(input.sending ? "offline.sending" : "offline.sendNow")) {
                    Task { await outbox.flush() }
                }
                .buttonStyle(.borderedProminent).tint(Color.warning)
                .disabled(input.sending)
                .frame(minHeight: 44)
            }
        }
    }
}
