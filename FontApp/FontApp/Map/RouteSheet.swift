import Charts
import SwiftUI
import UIKit

/// "Water on my route": the fountains along an imported GPX, by kilometre.
struct RouteSheet: View {
    @Bindable var route: RouteModel
    let onShow: (FontSummary) -> Void
    let onForget: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var shared: SharedFile?

    var body: some View {
        NavigationStack {
            List {
                switch route.state {
                case .loading:
                    ProgressView().frame(maxWidth: .infinity)
                case .failed(let message):
                    Text(message).foregroundStyle(.secondary)
                case .loaded:
                    summary
                    stops
                }
                Section {
                    Text(L10n.t("ios.gpx.privacy")).font(.footnote).foregroundStyle(.secondary)
                    Button(L10n.t("gpxIn.forget"), role: .destructive) {
                        onForget()
                        dismiss()
                    }
                    .frame(minHeight: 44)
                }
            }
            .navigationTitle(L10n.t("gpxIn.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button(role: .close) { dismiss() } }
            }
            .sheet(item: $shared) { ActivityView(items: [$0.url]) }
        }
    }

    private var summary: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(route.name).font(.headline)
                Text(L10n.t("gpxIn.summary", ["km": RouteModel.km(route.lengthKm), "n": route.onRoute.count]))
                if route.onRoute.isEmpty {
                    Text(L10n.t("gpxIn.driestAll")).foregroundStyle(.orange)
                } else {
                    Text(stretch("gpxIn.driest", route.driest))
                    // Said a second time only when it changes something: counting fountains
                    // nobody has checked, "2 km" can really be the whole route.
                    let sure = route.driestWithWater
                    if sure != route.driest {
                        Text(stretch("gpxIn.driestSure", sure)).foregroundStyle(.orange)
                    }
                    if let climb = route.driestClimb {
                        Text(L10n.t("gpxIn.driestClimb", ["a": RouteModel.km(climb.stretch.fromKm),
                                                          "b": RouteModel.km(climb.stretch.toKm), "m": climb.meters]))
                    }
                }
            }
            .padding(.vertical, 4)
            if route.profile.count >= 2 {
                RouteProfileChart(profile: route.profile, stops: route.onRoute)
                    .frame(height: 140)
                    .padding(.vertical, 4)
            }
            Picker(L10n.t("gpxIn.corridor"), selection: $route.corridor) {
                ForEach(GPX.corridors, id: \.self) { meters in
                    Text("\(Int(meters)) m").tag(meters)
                }
            }
            if !route.onRoute.isEmpty {
                // The button says how many go: the GPS unit gets what was chosen.
                Button {
                    shared = SharedFile.write(route.gpx(), name: GPX.fileName())
                } label: {
                    Label(L10n.t("gpxIn.exportN", ["n": min(route.chosen.count, GPX.maxWaypoints)]),
                          systemImage: "square.and.arrow.up")
                        .frame(minHeight: 44, alignment: .leading)
                }
                .disabled(route.chosen.isEmpty)
                if route.chosen.count > GPX.maxWaypoints {
                    // It says so: the file used to be cut silently.
                    Text(L10n.t("gpxIn.tooMany", ["n": GPX.maxWaypoints, "total": route.chosen.count]))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder private var stops: some View {
        if route.onRoute.isEmpty {
            Text(L10n.t("gpxIn.none")).foregroundStyle(.secondary)
        } else {
            Section {
                ForEach(route.onRoute) { stop in
                    HStack(spacing: 10) {
                        // Whether it goes to the GPS unit. The row itself opens the fountain.
                        Button {
                            route.toggle(stop)
                        } label: {
                            Image(systemName: route.isChosen(stop) ? "checkmark.circle.fill" : "circle")
                                .font(.title2)
                                .foregroundStyle(route.isChosen(stop) ? Color.accentColor : .secondary)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.t("gpxIn.takeAria", ["name": L10n.fontName(stop.font.name)]))
                        .accessibilityAddTraits(route.isChosen(stop) ? .isSelected : [])
                        Button {
                            dismiss()
                            onShow(stop.font)
                        } label: {
                            StopRow(stop: stop)
                        }
                        .foregroundStyle(.primary)
                    }
                    .swipeActions(edge: .leading) {
                        Button(L10n.t("gpxIn.fromHere")) { route.onlyFrom(stop) }.tint(.accentColor)
                    }
                    .contextMenu {
                        Button(L10n.t("gpxIn.fromHere"), systemImage: "arrow.down.to.line") { route.onlyFrom(stop) }
                    }
                }
            } header: {
                HStack {
                    Text(L10n.t("gpxIn.selected", ["n": route.chosen.count, "m": route.onRoute.count]))
                    Spacer()
                    Button(L10n.t("gpxIn.selectAll")) { route.chooseAll() }.font(.footnote)
                    Button(L10n.t("gpxIn.selectNone")) { route.chooseNone() }.font(.footnote)
                }
            } footer: {
                Text(L10n.t("gpxIn.selectHint"))
            }
        }
    }

    private func stretch(_ key: String, _ s: GPX.DryStretch) -> String {
        L10n.t(key, ["km": RouteModel.km(s.lengthKm), "a": RouteModel.km(s.fromKm), "b": RouteModel.km(s.toKm)])
    }
}

private struct StopRow: View {
    let stop: GPX.OnRoute

    var body: some View {
        HStack(spacing: 12) {
            Text(L10n.t("gpxIn.km", ["km": RouteModel.km(stop.km)]))
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .frame(width: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.fontName(stop.font.name))
                if let status = WaterStatus(stop.font.lastWaterStatus) {
                    StatusBadge(status: status).font(.caption).fixedSize()
                }
                Text(L10n.t("gpxIn.detour", ["m": stop.detour]))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 44)
    }
}

/// The elevation profile with the fountains on it: a cyclist reads a profile natively,
/// and on it one sees at a glance that the long climb has none. A minimum of 50 m of
/// range, or an almost flat route is drawn as a saw.
private struct RouteProfileChart: View {
    let profile: [GPX.ProfilePoint]
    let stops: [GPX.OnRoute]

    var body: some View {
        let low = profile.map(\.elevation).min() ?? 0
        let high = max(profile.map(\.elevation).max() ?? 0, low + 50)
        Chart {
            ForEach(Array(profile.enumerated()), id: \.offset) { _, point in
                AreaMark(x: .value("km", point.km), yStart: .value("m", low), yEnd: .value("m", point.elevation))
                    .foregroundStyle(Color.secondary.opacity(0.15))
                LineMark(x: .value("km", point.km), y: .value("m", point.elevation))
                    .foregroundStyle(Color.secondary)
            }
            ForEach(stops) { stop in
                PointMark(x: .value("km", stop.km), y: .value("m", elevation(at: stop.km)))
                    .foregroundStyle(WaterStatus.color(for: stop.font.lastWaterStatus))
                    .symbolSize(60)
            }
        }
        .chartYScale(domain: low...high)
        .chartXAxisLabel("km")
        .chartYAxisLabel("m")
        .accessibilityLabel(L10n.t("gpxIn.profile", ["min": Int(low), "max": Int(high)]))
    }

    private func elevation(at km: Double) -> Double {
        profile.min { abs($0.km - km) < abs($1.km - km) }?.elevation ?? 0
    }
}

/// A file written to share, with the system share sheet (AirDrop, Files, Garmin Connect…).
struct SharedFile: Identifiable {
    let url: URL
    var id: URL { url }

    static func write(_ text: String, name: String) -> SharedFile? {
        let url = FileManager.default.temporaryDirectory.appending(path: name)
        guard (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil else { return nil }
        return SharedFile(url: url)
    }
}

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
