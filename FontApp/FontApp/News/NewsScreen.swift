import SwiftUI

/// What has happened lately: new fountains, reviews and reports, with a photo.
struct NewsScreen: View {
    @Environment(LocationService.self) private var location
    @State private var model = NewsModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                scopePicker
                content
            }
            .navigationTitle(L10n.t("news.title"))
            .navigationDestination(for: UUID.self) { FontDetailView(fontID: $0) }
            .toolbar {
                if model.effectiveScope(location: location.location) == .near {
                    ToolbarItem(placement: .topBarTrailing) { radiusMenu }
                }
            }
            .refreshable { await model.reload(location: location.location) }
        }
        .task(id: ReloadKey(scope: model.effectiveScope(location: location.location), km: model.km)) {
            await model.reload(location: location.location)
        }
    }

    /// What makes the list stale. A new GPS fix is not in it on purpose.
    private struct ReloadKey: Equatable {
        let scope: NewsModel.Scope
        let km: Double
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .idle, .loading where model.items.isEmpty:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message) where model.items.isEmpty:
            ContentUnavailableView {
                Label(L10n.t("activity.errorTitle"), systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button(L10n.t("activity.retry")) {
                    Task { await model.reload(location: location.location) }
                }
                .buttonStyle(.bordered)
            }
        default:
            if model.items.isEmpty {
                emptyState
            } else {
                list
            }
        }
    }

    private var list: some View {
        List {
            ForEach(model.items, id: \.self) { item in
                NavigationLink(value: item.fontID) { ActivityRow(item: item) }
            }
            if model.canLoadMore {
                Button {
                    Task { await model.loadMore() }
                } label: {
                    HStack {
                        Text(L10n.t("activity.loadMore"))
                        if model.isLoadingMore { Spacer(); ProgressView() }
                    }
                    .frame(minHeight: 44)
                }
                .disabled(model.isLoadingMore)
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder private var emptyState: some View {
        let near = model.effectiveScope(location: location.location) == .near
        ContentUnavailableView {
            Label(L10n.t(near ? "activity.emptyNearTitle" : "activity.emptyTitle"), systemImage: "drop")
        } description: {
            Text(L10n.t(near ? "activity.emptyNearBody" : "activity.emptyBody"))
        }
    }

    /// "Near me" only with a position; without one the feed is global and says so.
    private var scopePicker: some View {
        // Shows the scope in use: without a position that is "everywhere", whatever was
        // chosen, and the choice itself is kept for when the position comes back.
        Picker(selection: Binding(get: { model.effectiveScope(location: location.location) },
                                  set: { model.scope = $0 })) {
            Text(L10n.t("activity.nearMe")).tag(NewsModel.Scope.near)
            Text(L10n.t("activity.everywhere")).tag(NewsModel.Scope.everywhere)
        } label: {
            EmptyView()
        }
        .pickerStyle(.segmented)
        .disabled(location.location == nil)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var radiusMenu: some View {
        Menu {
            Picker(L10n.t("activity.radius"), selection: $model.km) {
                ForEach(NewsModel.radii, id: \.self) { km in
                    Text("\(Int(km)) km").tag(km)
                }
            }
        } label: {
            Label("\(L10n.t("activity.radius")): \(Int(model.km)) km", systemImage: "scope")
        }
    }
}

private struct ActivityRow: View {
    let item: ActivityItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.fontName(item.fontName))
                    .font(.headline)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if let kind = kindLabel {
                        Text(kind).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let status = WaterStatus(item.waterStatus) {
                        StatusBadge(status: status).font(.caption)
                    }
                }
                if let text = item.text, !text.isEmpty {
                    Text(text).font(.subheadline).lineLimit(3)
                }
                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }

    private var kindLabel: String? {
        item.kind == .other ? nil : L10n.lookup("activity.\(item.kind.rawValue)")
    }

    private var footer: String {
        [RelativeTime.string(since: item.createdAt), item.author ?? L10n.t("activity.anon"), item.region]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private var thumbnail: some View {
        Group {
            if let url = APIClient.shared.imageURL(item.image) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color(.secondarySystemFill)
                }
            } else {
                Color(.secondarySystemFill)
                    .overlay {
                        Image(systemName: "drop.fill")
                            .foregroundStyle(WaterStatus.color(for: item.waterStatus))
                    }
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityHidden(true)
    }
}
