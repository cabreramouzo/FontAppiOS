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
                }
            }
            .padding(.vertical, 4)
            Picker(L10n.t("gpxIn.corridor"), selection: $route.corridor) {
                ForEach(GPX.corridors, id: \.self) { meters in
                    Text("\(Int(meters)) m").tag(meters)
                }
            }
            if !route.onRoute.isEmpty {
                Button {
                    shared = SharedFile.write(route.gpx(), name: GPX.fileName())
                } label: {
                    Label(L10n.t("gpxIn.exportN", ["n": min(route.onRoute.count, GPX.maxWaypoints)]),
                          systemImage: "square.and.arrow.up")
                        .frame(minHeight: 44, alignment: .leading)
                }
                if route.onRoute.count > GPX.maxWaypoints {
                    Text(L10n.t("gpxIn.tooMany", ["n": GPX.maxWaypoints, "total": route.onRoute.count]))
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
                    Button {
                        dismiss()
                        onShow(stop.font)
                    } label: {
                        HStack(spacing: 12) {
                            Text(L10n.t("gpxIn.km", ["km": RouteModel.km(stop.km)]))
                                .font(.subheadline.monospacedDigit().weight(.semibold))
                                .frame(width: 64, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.fontName(stop.font.name))
                                HStack(spacing: 6) {
                                    if let status = WaterStatus(stop.font.lastWaterStatus) {
                                        StatusBadge(status: status).font(.caption)
                                    }
                                    Text(L10n.t("gpxIn.detour", ["m": stop.detour]))
                                        .font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .frame(minHeight: 44)
                    }
                    .foregroundStyle(.primary)
                }
            }
        }
    }

    private func stretch(_ key: String, _ s: GPX.DryStretch) -> String {
        L10n.t(key, ["km": RouteModel.km(s.lengthKm), "a": RouteModel.km(s.fromKm), "b": RouteModel.km(s.toKm)])
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
