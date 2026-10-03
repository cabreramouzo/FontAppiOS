import AppIntents
import SwiftUI
import WidgetKit

struct FavoriteEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "widget.favorite.name"
    static var defaultQuery = FavoriteQuery()
    let id: String
    let name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct FavoriteQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [FavoriteEntity] {
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [FavoriteEntity] {
        guard let snapshot = WidgetFavoritesStore.read() else { return [] }
        return snapshot.fountains.map {
            FavoriteEntity(id: WidgetFavoritesStore.identifier($0, in: snapshot), name: Status.name($0.name))
        }
    }
}

struct FavoriteConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "widget.favorite.name"
    @Parameter(title: "widget.favorite.choose") var fountain: FavoriteEntity?
    @Parameter(title: "widget.favorite.chooseSecond") var secondFountain: FavoriteEntity?
    @Parameter(title: "widget.favorite.chooseThird") var thirdFountain: FavoriteEntity?

    static var parameterSummary: some ParameterSummary {
        Switch(.widgetFamily) {
            Case(.systemMedium) {
                Summary { \.$fountain; \.$secondFountain; \.$thirdFountain }
            }
            DefaultCase { Summary { \.$fountain } }
        }
    }
}

struct FavoriteEntry: TimelineEntry {
    let date: Date
    var fountain: WidgetFavorite?
    var message = "widget.favorite.chooseHint"
    var cached = false
    var additional: [FavoriteEntry] = []

    static var mediumSample: Self {
        var entry = sample
        entry.additional = [sample, sample]
        return entry
    }

    static var sample: Self {
        Self(date: .now, fountain: WidgetFavorite(id: UUID(), name: "Font del Faig",
             lastWaterStatus: "flowing", lastUpdate: .now.addingTimeInterval(-2 * 86_400), conflict: false))
    }
}

struct FavoriteProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> FavoriteEntry { .sample }
    func snapshot(for configuration: FavoriteConfiguration, in context: Context) async -> FavoriteEntry {
        context.isPreview ? .sample : await load(configuration, family: context.family)
    }
    func timeline(for configuration: FavoriteConfiguration, in context: Context) async -> Timeline<FavoriteEntry> {
        Timeline(entries: [await load(configuration, family: context.family)], policy: .after(.now.addingTimeInterval(30 * 60)))
    }

    private func load(_ configuration: FavoriteConfiguration, family: WidgetFamily) async -> FavoriteEntry {
        let entities = family == .systemMedium
            ? [configuration.fountain, configuration.secondFountain, configuration.thirdFountain]
            : [configuration.fountain]
        var seen = Set<String>()
        let identifiers = entities.compactMap { $0?.id }.filter { seen.insert($0).inserted }
        guard !identifiers.isEmpty else { return await loadSelection(nil) }
        var entries: [FavoriteEntry] = []
        for identifier in identifiers { entries.append(await loadSelection(identifier)) }
        // Revalidate every row after all requests, including account changes between requests.
        for index in entries.indices {
            if WidgetFavoritesStore.selected(identifiers[index], in: WidgetFavoritesStore.read()) == nil {
                entries[index] = FavoriteEntry(date: .now, message: "widget.favorite.removed")
            }
        }
        var entry = entries.removeFirst()
        entry.additional = entries
        return entry
    }

    private func loadSelection(_ selection: String?) async -> FavoriteEntry {
        guard let snapshot = WidgetFavoritesStore.read() else {
            return FavoriteEntry(date: .now, message: "widget.favorite.signIn")
        }
        guard let identifier = selection else { return FavoriteEntry(date: .now) }
        guard let saved = WidgetFavoritesStore.selected(identifier, in: snapshot) else {
            return FavoriteEntry(date: .now, message: "widget.favorite.removed")
        }
        // A separate public cache keeps a successful widget refresh when the next one fails.
        let defaults = UserDefaults(suiteName: WidgetFavoritesStore.group)
        let cacheKey = "widget.detail.\(identifier)"
        let cached = defaults?.data(forKey: cacheKey).flatMap { try? JSONDecoder().decode(WidgetFavorite.self, from: $0) }
        var fountain = saved
        if let cached, cached.unavailable || (cached.lastUpdate ?? .distantPast) > (saved.lastUpdate ?? .distantPast) {
            fountain = cached
        }
        var failed = true
        do {
            var request = URLRequest(url: snapshot.baseURL.appending(path: "fonts/\(saved.id.uuidString)"))
            request.timeoutInterval = 8
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode
            if status == 404 {
                fountain.unavailable = true
                failed = false
            } else if status == 200 {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .custom { decoder in
                    let text = try decoder.singleValueContainer().decode(String.self)
                    if let date = try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) { return date }
                    return try Date(text, strategy: .iso8601)
                }
                let detail = try decoder.decode(Detail.self, from: data)
                guard detail.id == saved.id else { throw URLError(.badServerResponse) }
                fountain = WidgetFavorite(id: detail.id, name: detail.name, lastWaterStatus: detail.lastWaterStatus,
                    lastUpdate: detail.lastUpdate, conflict: detail.statusConflict ?? false,
                    unavailable: detail.duplicateOf != nil || detail.retiredAt != nil ||
                        (detail.moderationState != nil && detail.moderationState != "visible"))
                failed = false
            }
        } catch { /* A failed refresh keeps the known report, never a claim of fresh data. */ }
        // Account switch, sign-out or unstar while the network request was running.
        guard WidgetFavoritesStore.selected(identifier, in: WidgetFavoritesStore.read()) != nil else {
            return FavoriteEntry(date: .now, message: "widget.favorite.removed")
        }
        if !failed { defaults?.set(try? JSONEncoder().encode(fountain), forKey: cacheKey) }
        return FavoriteEntry(date: .now, fountain: fountain, cached: failed)
    }

    private struct Detail: Decodable {
        let id: UUID
        let name: String?
        let lastWaterStatus: String?
        let lastUpdate: Date?
        let statusConflict: Bool?
        let duplicateOf: UUID?
        let retiredAt: Date?
        let moderationState: String?
    }
}

struct FavoriteWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetFavoritesStore.kind, intent: FavoriteConfiguration.self,
                               provider: FavoriteProvider()) { entry in
            FavoriteView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(String(localized: "widget.favorite.name"))
        .description(String(localized: "widget.favorite.description"))
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct FavoriteView: View {
    let entry: FavoriteEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if family == .systemMedium, !entry.additional.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(([entry] + entry.additional).enumerated()), id: \.offset) { index, item in
                        if index > 0 { Divider() }
                        Link(destination: item.fountain.map { Status.url($0.id) } ?? URL(string: "https://fontapp.net")!) {
                            row(item)
                        }
                    }
                }
            } else {
                single
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(entry.additional.isEmpty ? entry.fountain.map { Status.url($0.id) } ?? URL(string: "https://fontapp.net") : nil)
    }

    private var single: some View {
        VStack(alignment: .leading, spacing: family == .accessoryRectangular ? 2 : 6) {
            if let font = entry.fountain {
                if family != .accessoryRectangular {
                    Label(String(localized: "widget.favorite.name"), systemImage: "star.fill")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Text(Status.name(font.name)).font(.headline).lineLimit(family == .systemSmall ? 2 : 1)
                Text("\(emoji(font)) \(label(font))").font(.subheadline.weight(.semibold)).lineLimit(2)
                    .foregroundStyle(font.conflict || font.unavailable ? .secondary : Status.color(font.lastWaterStatus))
                reportDate(font)
                if family != .accessoryRectangular {
                    Spacer(minLength: 0)
                    if entry.cached { Text("widget.favorite.cached").font(.caption2).foregroundStyle(.secondary) }
                }
            } else { empty(entry) }
        }
    }

    @ViewBuilder private func row(_ item: FavoriteEntry) -> some View {
        if let font = item.fountain {
            HStack(spacing: 8) {
                VStack(spacing: 0) {
                    Text(emoji(font)).font(.title3).accessibilityHidden(true)
                    if item.cached {
                        Image(systemName: "wifi.slash").font(.system(size: 9))
                            .foregroundStyle(.secondary).accessibilityLabel(Text("widget.favorite.cached"))
                    }
                }
                VStack(alignment: .leading, spacing: 1) {
                    HStack {
                        Text(Status.name(font.name)).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(label(font)).font(.caption).lineLimit(1)
                            .foregroundStyle(font.conflict || font.unavailable ? .secondary : Status.color(font.lastWaterStatus))
                    }
                    reportDate(font)
                }
            }
            .accessibilityElement(children: .combine)
        } else { empty(item) }
    }

    private func empty(_ item: FavoriteEntry) -> some View {
        Text(String(localized: String.LocalizationValue(item.message))).font(.caption).lineLimit(2)
    }

    @ViewBuilder private func reportDate(_ font: WidgetFavorite) -> some View {
        if let date = font.lastUpdate, font.lastWaterStatus != nil {
            (Text("widget.favorite.reportDate") + Text(": ") + Text(date, format: .dateTime.day().month().year()))
                .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
        } else {
            Text("widget.favorite.noDate").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func emoji(_ font: WidgetFavorite) -> String {
        if font.unavailable { return "📍" }
        if font.conflict { return "⚠️" }
        switch font.lastWaterStatus {
        case "flowing": return "💧"
        case "trickle": return "💦"
        case "dry": return "🚱"
        case "broken": return "🛠️"
        case "gone": return "🪦"
        default: return "❔"
        }
    }

    private func label(_ font: WidgetFavorite) -> String {
        if font.unavailable { return String(localized: "widget.favorite.unavailable") }
        if font.conflict { return String(localized: "confidence.disputed") }
        return Status.label(font.lastWaterStatus)
    }
}

#Preview(as: .systemSmall) { FavoriteWidget() } timeline: { FavoriteEntry.sample }
#Preview(as: .accessoryRectangular) { FavoriteWidget() } timeline: { FavoriteEntry.sample }

#Preview(as: .systemMedium) { FavoriteWidget() } timeline: { FavoriteEntry.mediumSample }
