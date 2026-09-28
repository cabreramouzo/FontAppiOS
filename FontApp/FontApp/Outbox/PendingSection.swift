import SwiftUI

/// What is saved on the phone and not sent yet, with a way to send it now or drop it.
///
/// Dropping must exist: a contribution that can never go out (another account's, or one
/// already published by hand) would otherwise sit here for ever. It is destructive — the
/// data exist only on this phone — so it asks first.
struct PendingSection: View {
    @Environment(Outbox.self) private var outbox
    @State private var confirmsDiscard = false

    var body: some View {
        if !outbox.items.isEmpty {
            Section {
                ForEach(outbox.items) { PendingRow(item: $0, mine: !outbox.isOthers($0)) }
                Button {
                    Task { await outbox.flush() }
                } label: {
                    HStack {
                        Text(L10n.t(outbox.isFlushing ? "offline.sending" : "offline.sendNow"))
                        if outbox.isFlushing { Spacer(); ProgressView() }
                    }
                    .frame(minHeight: 44)
                }
                .disabled(outbox.isFlushing || outbox.mine.isEmpty)
                Button(L10n.t("offline.discard"), role: .destructive) { confirmsDiscard = true }
                    .frame(minHeight: 44)
                    .confirmationDialog(L10n.t("offline.discardConfirm", ["n": outbox.items.count]),
                                        isPresented: $confirmsDiscard, titleVisibility: .visible) {
                        Button(L10n.t("offline.discard"), role: .destructive) { outbox.discard() }
                    }
            } header: {
                Text(L10n.t("offline.pending", ["n": outbox.items.count]))
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if outbox.needsAuth {
                        Text(L10n.t("offline.needsLogin"))
                    } else {
                        Text(L10n.t("offline.pendingHint"))
                    }
                    if outbox.othersCount > 0 {
                        Text(L10n.t("offline.otherAccount", ["n": outbox.othersCount]))
                    }
                }
            }
        }
    }
}

private struct PendingRow: View {
    let item: OutboxItem
    let mine: Bool

    private var kindKey: String {
        switch item.kind {
        case .review, .comment: "offline.itemReview"
        case .photo: "offline.itemPhoto"
        case .font: "offline.itemFont"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(L10n.t(kindKey))
                    .font(.subheadline.weight(.semibold))
                if let status = WaterStatus(item.review?.waterStatus) {
                    StatusBadge(status: status).font(.caption)
                }
                Spacer()
                Text(RelativeTime.string(since: item.queuedAt))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Text(L10n.fontName(item.fontName))
            let notes = [
                mine ? nil : L10n.t("offline.itemOther"),
                item.needsAuth ? L10n.t("offline.itemNeedsAuth") : nil,
                item.attempts > 0 ? L10n.t("offline.attempts", ["n": item.attempts]) : nil,
            ].compactMap { $0 }
            if !notes.isEmpty {
                Text(notes.joined(separator: " · ")).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
