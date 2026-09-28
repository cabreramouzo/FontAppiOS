import SwiftUI

/// What has happened lately: new fountains, reviews and reports, with a photo.
struct NewsScreen: View {
    @Environment(LocationService.self) private var location
    @Environment(SessionStore.self) private var session
    @State private var model = NewsModel()
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack {
            // The list is the root, so the large title folds away on scrolling. The filters
            // live in one toolbar menu and the choice in effect reads under the title: two
            // pickers stacked above the list took a third of the screen for good.
            content
            .navigationTitle(L10n.t("news.title"))
            .navigationSubtitle(filterSummary)
            .navigationDestination(for: UUID.self) { FontDetailView(fontID: $0) }
            .toolbar {
                if session.isSignedIn { ToolbarItem(placement: .topBarLeading) { BellButton() } }
                ToolbarItem(placement: .topBarTrailing) { filterMenu }
            }
            .refreshable { await model.reload(location: location.location) }
        }
        .task(id: ReloadKey(scope: model.effectiveScope(location: location.location), km: model.km, country: model.country)) {
            await model.reload(location: location.location)
        }
    }

    /// What makes the list stale. A new GPS fix is not in it on purpose.
    private struct ReloadKey: Equatable {
        let scope: NewsModel.Scope
        let km: Double
        let country: String
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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                Text(L10n.t("news.intro"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if case .failed(let message) = model.state {
                    Label(message, systemImage: "wifi.exclamationmark")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if let first = model.items.first {
                    NavigationLink(value: first.fontID) {
                        ActivityCard(item: first, prominent: true)
                    }
                    .buttonStyle(.plain)
                }
                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    ForEach(Array(model.items.dropFirst()), id: \.self) { item in
                        NavigationLink(value: item.fontID) {
                            ActivityCard(item: item, prominent: dynamicTypeSize.isAccessibilitySize)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if model.canLoadMore {
                    Button {
                        Task { await model.loadMore() }
                    } label: {
                        HStack {
                            Spacer()
                            Text(L10n.t("activity.loadMore"))
                            if model.isLoadingMore { ProgressView() }
                            Spacer()
                        }
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.isLoadingMore)
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top),
              count: dynamicTypeSize.isAccessibilitySize ? 1 : 2)
    }

    @ViewBuilder private var emptyState: some View {
        let near = model.effectiveScope(location: location.location) == .near
        ContentUnavailableView {
            Label(L10n.t(near ? "activity.emptyNearTitle" : "activity.emptyTitle"), systemImage: "drop")
        } description: {
            Text(L10n.t(near ? "activity.emptyNearBody" : "activity.emptyBody"))
        }
    }

    /// What the feed shows, under the title: "Near me · 5 km", "Everywhere · Spain".
    private var filterSummary: String {
        if model.effectiveScope(location: location.location) == .near {
            return "\(L10n.t("activity.nearMe")) · \(Int(model.km)) km"
        }
        return "\(L10n.t("activity.everywhere")) · \(countryName)"
    }

    private var countryName: String {
        model.country == NewsModel.allCountries
            ? L10n.t("zones.allCountries")
            : L10n.lookup("country.\(model.country)") ?? model.country
    }

    /// Scope, then the radius or the country that goes with it. "Near me" only with a
    /// position; without one the feed is global and the menu says so by disabling it.
    private var filterMenu: some View {
        Menu {
            Picker(selection: Binding(get: { model.effectiveScope(location: location.location) },
                                      set: { model.scope = $0 })) {
                Label(L10n.t("activity.nearMe"), systemImage: "location").tag(NewsModel.Scope.near)
                Label(L10n.t("activity.everywhere"), systemImage: "globe").tag(NewsModel.Scope.everywhere)
            } label: {
                EmptyView()
            }
            .pickerStyle(.inline)
            .disabled(location.location == nil)
            if model.effectiveScope(location: location.location) == .near {
                Picker(selection: $model.km) {
                    ForEach(NewsModel.radii, id: \.self) { km in
                        Text("\(Int(km)) km").tag(km)
                    }
                } label: {
                    Label(L10n.t("activity.radius"), systemImage: "scope")
                    Text("\(Int(model.km)) km")
                }
                .pickerStyle(.menu)
            } else {
                Picker(selection: $model.country) {
                    Text(L10n.t("zones.allCountries")).tag(NewsModel.allCountries)
                    ForEach(NewsModel.countries, id: \.self) { country in
                        Text(L10n.lookup("country.\(country)") ?? country).tag(country)
                    }
                } label: {
                    Label(L10n.t("activity.country"), systemImage: "flag")
                    Text(countryName)
                }
                .pickerStyle(.menu)
            }
        } label: {
            Label(L10n.t("map.filters"), systemImage: "line.3.horizontal.decrease")
        }
    }
}

/// Photo-led bulletin cards. Text determines height, so Dynamic Type never clips copy.
private struct ActivityCard: View {
    let item: ActivityItem
    var prominent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                if let kind = kindLabel {
                    Label(kind, systemImage: kindIcon)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(item.kind == .report ? Color.orange.opacity(0.85) : Color.black.opacity(0.65),
                                    in: Capsule())
                }
                Spacer(minLength: 0)
            }
            Spacer(minLength: prominent ? 72 : 40)
            VStack(alignment: .leading, spacing: 8) {
                if let status = WaterStatus(item.waterStatus) {
                    Text("\(status.emoji) \(L10n.t(status.labelKey))")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.6), in: Capsule())
                }
                Text(L10n.fontName(item.fontName))
                    .font(prominent ? .title2.bold() : .headline)
                    .fixedSize(horizontal: false, vertical: true)
                if let text = item.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                    Text(text)
                        .font(.subheadline)
                        .lineLimit(prominent ? 4 : 3)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.author ?? L10n.t("activity.anon"))
                    Text([RelativeTime.string(since: item.createdAt), item.region]
                        .compactMap { $0 }.joined(separator: " · "))
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
            }
        }
        .padding(prominent ? 18 : 13)
        .frame(maxWidth: .infinity, minHeight: prominent ? 300 : 250, alignment: .leading)
        .foregroundStyle(.white)
        .background {
            GeometryReader { geometry in
                ZStack {
                    fallback
                    if let url = APIClient.shared.imageURL(item.image) {
                        AsyncImage(url: url) { phase in
                            if case .success(let image) = phase {
                                image.resizable().scaledToFill()
                            }
                        }
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
                .overlay {
                    LinearGradient(colors: [.black.opacity(0.12), .black.opacity(0.65), .black.opacity(0.95)],
                                   startPoint: .top, endPoint: .bottom)
                }
            }
            .accessibilityHidden(true)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(item.kind == .report ? Color.orange.opacity(0.7) : Color.white.opacity(0.12),
                              lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    /// A decorative drawing, never a pretend photograph of an undocumented fountain.
    private var fallback: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(colors: [Color(hex: 0x326C78), Color(hex: 0x183940)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "water.waves")
                .font(.system(size: prominent ? 140 : 90, weight: .ultraLight))
                .foregroundStyle(.white.opacity(0.16))
                .rotationEffect(.degrees(-20))
                .padding(.top, 42)
                .padding(.trailing, -15)
        }
    }

    private var kindLabel: String? {
        item.kind == .other ? nil : L10n.lookup("activity.\(item.kind.rawValue)")
    }

    private var kindIcon: String {
        switch item.kind {
        case .fontAdded: "plus.circle.fill"
        case .review: "text.bubble.fill"
        case .report: "exclamationmark.triangle.fill"
        case .edit: "pencil"
        case .other: "drop.fill"
        }
    }
}
