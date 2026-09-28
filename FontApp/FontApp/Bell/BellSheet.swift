import SwiftUI

/// The bell in a toolbar: a dot when something is new. Only for a signed-in account.
struct BellButton: View {
    @Environment(Bell.self) private var bell
    @State private var isOpen = false

    var body: some View {
        Button { isOpen = true } label: {
            Label(L10n.t("notif.bell"), systemImage: bell.unread > 0 ? "bell.badge" : "bell")
                .symbolRenderingMode(bell.unread > 0 ? .palette : .monochrome)
                .foregroundStyle(.red, .primary)
        }
        .accessibilityValue(bell.unread > 0 ? "\(bell.unread)" : "")
        .accessibilityIdentifier("bell")
        .sheet(isPresented: $isOpen) { BellSheet() }
    }
}

/// The inbox: the last notices, new ones marked, each leading to its fountain.
struct BellSheet: View {
    @Environment(Bell.self) private var bell
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(L10n.t("notif.bell"))
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: UUID.self) { FontDetailView(fontID: $0) }
                .profileNavigation()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { Button(role: .close) { dismiss() } }
                }
                .refreshable { await bell.reload() }
        }
        .task {
            await bell.reload()
            await bell.opened()
        }
    }

    @ViewBuilder private var content: some View {
        if bell.items.isEmpty {
            switch bell.state {
            case .idle, .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ContentUnavailableView {
                    Label(L10n.t("notif.bell"), systemImage: "bell.slash")
                } description: {
                    Text(message)
                } actions: {
                    Button(L10n.t("activity.retry")) { Task { await bell.reload() } }
                }
            case .loaded:
                ContentUnavailableView {
                    Label(L10n.t("notif.bell"), systemImage: "bell")
                } description: {
                    Text(L10n.t("ios.bell.empty"))
                }
            }
        } else {
            List(bell.items) { item in
                // A deleted fountain: the notice stays, but no longer leads anywhere.
                if let fontID = item.fontID {
                    NavigationLink(value: fontID) { NotificationRow(item: item) }
                } else {
                    NotificationRow(item: item)
                }
            }
            .listStyle(.plain)
        }
    }
}

private struct NotificationRow: View {
    let item: NotificationItem
    @Environment(\.openProfile) private var openProfile

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: NotificationText.systemImage(item.kind))
                .font(.body)
                .foregroundStyle(item.read ? Color.secondary : Color.accentColor)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(NotificationText.title(item))
                    .font(.subheadline.weight(item.read ? .regular : .semibold))
                Text(NotificationText.body(item))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let date = item.createdAt {
                    Text(RelativeTime.string(since: date))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
            if !item.read {
                Circle().fill(Color.accentColor).frame(width: 8, height: 8)
                    .padding(.top, 6)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        // The row leads to the fountain; who did it is one long press away.
        .contextMenu {
            if let openProfile, !item.actorName.isEmpty {
                Button { openProfile(item.actorName) } label: {
                    Label { Text(verbatim: "@\(item.actorName)") } icon: { Image(systemName: "person.crop.circle") }
                }
            }
        }
    }
}
