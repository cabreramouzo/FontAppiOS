import CoreLocation
import SwiftUI
import WidgetKit

/// "Fountains near you", on the home and lock screens: the question people ask before
/// setting off — where is the nearest water and what is known about it — without
/// opening the app. Tapping a fountain opens its page.
///
/// Read-only public data (`GET /fonts/near`), so the widget talks to the server itself
/// and shares nothing with the app. It uses the app's location permission ("while using
/// the app or widgets"); without it, it says so instead of guessing a place.
@main
struct FontAppWidgets: WidgetBundle {
    var body: some Widget {
        NearbyWidget()
    }
}

struct NearbyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "nearby", provider: NearbyProvider()) { entry in
            NearbyView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(String(localized: "widget.name"))
        .description(String(localized: "widget.description"))
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: Data

/// Only what the widget draws, from the server's `FontSummary`.
struct NearbyFountain: Decodable, Identifiable, Sendable {
    let id: UUID
    let name: String?
    let latitude: Double
    let longitude: Double
    let lastWaterStatus: String?
    let lastUpdate: Date?
    var distance: CLLocationDistance = 0

    enum CodingKeys: String, CodingKey { case id, name, latitude, longitude, lastWaterStatus, lastUpdate }
}

struct NearbyEntry: TimelineEntry {
    enum State { case fountains([NearbyFountain]), noLocation, nothing, offline }
    let date: Date
    let state: State

    static let sample = NearbyEntry(date: .now, state: .fountains([
        NearbyFountain(id: UUID(), name: "Font del Faig", latitude: 0, longitude: 0,
                       lastWaterStatus: "flowing", lastUpdate: .now.addingTimeInterval(-2 * 3600), distance: 240),
        NearbyFountain(id: UUID(), name: nil, latitude: 0, longitude: 0,
                       lastWaterStatus: nil, lastUpdate: nil, distance: 610),
        NearbyFountain(id: UUID(), name: "Font de la Plaça", latitude: 0, longitude: 0,
                       lastWaterStatus: "trickle", lastUpdate: .now.addingTimeInterval(-9 * 86_400), distance: 1150),
    ]))
}

struct NearbyProvider: TimelineProvider {
    private static let base = URL(string: "https://fontapp.fly.dev")!

    func placeholder(in context: Context) -> NearbyEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping (NearbyEntry) -> Void) {
        if context.isPreview { completion(.sample); return }
        Task { completion(await Self.load()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NearbyEntry>) -> Void) {
        Task {
            let entry = await Self.load()
            // Half an hour: fresh enough for a walk, and within what iOS grants a widget.
            completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(30 * 60))))
        }
    }

    static func load() async -> NearbyEntry {
        guard let here = await WidgetLocation().current() else { return NearbyEntry(date: .now, state: .noLocation) }
        // About a hundred metres is enough to ask; the distances use the real position.
        let lat = (here.coordinate.latitude * 1000).rounded() / 1000
        let lon = (here.coordinate.longitude * 1000).rounded() / 1000
        var components = URLComponents(url: base.appending(path: "/fonts/near"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "lat", value: String(lat)),
                                 URLQueryItem(name: "long", value: String(lon)),
                                 URLQueryItem(name: "quantity", value: "3")]
        do {
            let (data, response) = try await URLSession.shared.data(from: components.url!)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return NearbyEntry(date: .now, state: .offline) }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { decoder in
                let text = try decoder.singleValueContainer().decode(String.self)
                return (try? Date(text, strategy: .iso8601))
                    ?? (try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
                    ?? .distantPast
            }
            var fonts = try decoder.decode([NearbyFountain].self, from: data)
            for index in fonts.indices {
                fonts[index].distance = here.distance(from: CLLocation(latitude: fonts[index].latitude,
                                                                       longitude: fonts[index].longitude))
            }
            fonts.sort { $0.distance < $1.distance }
            return NearbyEntry(date: .now, state: fonts.isEmpty ? .nothing : .fountains(fonts))
        } catch {
            return NearbyEntry(date: .now, state: .offline)
        }
    }
}

/// One position for the widget: the last known one if it is recent, otherwise a single
/// fix. Only with the app's permission extended to widgets.
final class WidgetLocation: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?

    func current() async -> CLLocation? {
        guard manager.isAuthorizedForWidgetUpdates else { return nil }
        if let last = manager.location, last.timestamp.timeIntervalSinceNow > -10 * 60 { return last }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.delegate = self
            manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        continuation?.resume(returning: locations.last)
        continuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        continuation?.resume(returning: manager.location)
        continuation = nil
    }
}

// MARK: Views

struct NearbyView: View {
    let entry: NearbyEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch entry.state {
        case .fountains(let fonts):
            switch family {
            case .systemMedium: medium(Array(fonts.prefix(3)))
            case .accessoryRectangular: rectangular(fonts[0])
            case .accessoryInline: inline(fonts[0])
            default: small(fonts[0])
            }
        case .noLocation: message("widget.noLocation", systemImage: "location.slash")
        case .nothing: message("widget.nothing", systemImage: "drop")
        case .offline: message("widget.offline", systemImage: "wifi.slash")
        }
    }

    private func small(_ font: NearbyFountain) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "drop.fill").foregroundStyle(Status.color(font.lastWaterStatus))
                Text(Status.label(font.lastWaterStatus)).font(.caption.weight(.semibold))
                    .foregroundStyle(Status.color(font.lastWaterStatus))
            }
            Text(Status.name(font.name)).font(.headline).lineLimit(3)
            Spacer(minLength: 0)
            Text(Status.distance(font.distance)).font(.title3.weight(.bold)).monospacedDigit()
            if let when = font.lastUpdate, font.lastWaterStatus != nil {
                Text(when, format: .relative(presentation: .named)).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(Status.url(font.id))
    }

    private func medium(_ fonts: [NearbyFountain]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(String(localized: "widget.name"), systemImage: "drop.fill")
                .font(.caption.weight(.bold)).foregroundStyle(.secondary)
            ForEach(fonts) { font in
                Link(destination: Status.url(font.id)) {
                    HStack(spacing: 8) {
                        Circle().fill(Status.color(font.lastWaterStatus)).frame(width: 10, height: 10)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(Status.name(font.name)).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text(Status.label(font.lastWaterStatus)).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(Status.distance(font.distance)).font(.subheadline.weight(.bold)).monospacedDigit()
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func rectangular(_ font: NearbyFountain) -> some View {
        VStack(alignment: .leading) {
            Text("\(Image(systemName: "drop.fill")) \(Status.distance(font.distance))").font(.headline)
            Text(Status.name(font.name)).lineLimit(1)
            Text(Status.label(font.lastWaterStatus)).foregroundStyle(.secondary)
        }
        .widgetURL(Status.url(font.id))
    }

    private func inline(_ font: NearbyFountain) -> some View {
        Text("\(Image(systemName: "drop.fill")) \(Status.distance(font.distance)) · \(Status.label(font.lastWaterStatus))")
    }

    private func message(_ key: String.LocalizationValue, systemImage: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage).font(.title2).foregroundStyle(.secondary)
            Text(String(localized: key)).font(.caption).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The app's words and colours for a status, kept to what the widget needs.
enum Status {
    static func color(_ raw: String?) -> Color {
        switch raw {
        case "flowing": Color(red: 0x22 / 255, green: 0xC5 / 255, blue: 0x5E / 255)
        case "trickle": Color(red: 0xF5 / 255, green: 0x9E / 255, blue: 0x0B / 255)
        case "dry": Color(red: 0xEF / 255, green: 0x44 / 255, blue: 0x44 / 255)
        case "broken": Color(red: 0xA8 / 255, green: 0x55 / 255, blue: 0xF7 / 255)
        case "gone": Color(red: 0x6B / 255, green: 0x72 / 255, blue: 0x80 / 255)
        case "unknown": Color(red: 0x9C / 255, green: 0xA3 / 255, blue: 0xAF / 255)
        default: Color(red: 0x3B / 255, green: 0x82 / 255, blue: 0xF6 / 255)
        }
    }

    static func label(_ raw: String?) -> String {
        switch raw {
        case "flowing": String(localized: "status.flowing")
        case "trickle": String(localized: "status.trickle")
        case "dry": String(localized: "status.dry")
        case "broken": String(localized: "status.broken")
        case "gone": String(localized: "status.gone")
        case "unknown": String(localized: "status.unknown")
        default: String(localized: "confidence.unverified")
        }
    }

    /// Three of four have no name: said in the reader's language, never invented.
    static func name(_ name: String?) -> String {
        guard let name, !name.isEmpty else { return String(localized: "font.unnamed") }
        return name
    }

    static func distance(_ meters: CLLocationDistance) -> String {
        let measurement = Measurement(value: meters, unit: UnitLength.meters)
        if meters < 1000 {
            return measurement.formatted(.measurement(width: .abbreviated, usage: .asProvided,
                                                      numberFormatStyle: .number.precision(.fractionLength(0))))
        }
        return measurement.converted(to: .kilometers)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided,
                                    numberFormatStyle: .number.precision(.fractionLength(1))))
    }

    /// The fountain's page on the web: the app opens it like a universal link.
    static func url(_ id: UUID) -> URL {
        URL(string: "https://fontapp.net/fonts/\(id.uuidString)")!
    }
}

#Preview(as: .systemSmall) { NearbyWidget() } timeline: { NearbyEntry.sample }
#Preview(as: .systemMedium) { NearbyWidget() } timeline: { NearbyEntry.sample }
