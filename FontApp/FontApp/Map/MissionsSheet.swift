import CoreLocation
import MapKit
import SwiftUI

/// "A walk around here": fountains nearby that are missing something — a photo, or a
/// check in over half a year. Two rounds, ordered by distance. Asks for the location only
/// from here, where the reason is on screen.
struct MissionsSheet: View {
    let onShow: (MissionTarget) -> Void
    let onShowRound: ([MissionTarget]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(LocationService.self) private var location
    @State private var state: LoadState = .idle

    enum LoadState {
        case idle, loading
        case loaded(Missions)
        case failed
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(L10n.t("mission.subtitle")).foregroundStyle(.secondary)
                }
                content
            }
            .navigationTitle(L10n.t("mission.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button(role: .close) { dismiss() } }
            }
            .task(id: location.location == nil) { await load() }
        }
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .idle where location.location == nil:
            Section {
                Text(L10n.t("mission.needLocation")).foregroundStyle(.secondary)
                Button(L10n.t("mission.locate")) { location.requestIfNeeded() }
                    .frame(minHeight: 44)
            }
        case .idle, .loading:
            HStack {
                ProgressView()
                Text(L10n.t("mission.locating")).foregroundStyle(.secondary)
            }
        case .failed:
            Section {
                Text(L10n.t("mission.failed")).foregroundStyle(.secondary)
                Button(L10n.t("mission.retry")) { Task { await load() } }.frame(minHeight: 44)
            }
        case .loaded(let missions):
            if missions.photoless.isEmpty && missions.stale.isEmpty {
                Text(L10n.t("mission.none")).foregroundStyle(.secondary)
            } else {
                round(title: "mission.photoless", hint: "mission.photolessHint", icon: "camera",
                      stops: missions.photoless, km: missions.km)
                round(title: "mission.summerRound", hint: "mission.summerRoundHint", icon: "clock.arrow.circlepath",
                      stops: missions.stale, km: missions.km)
            }
        }
    }

    @ViewBuilder
    private func round(title: String, hint: String, icon: String, stops: [MissionTarget], km: Double) -> some View {
        if !stops.isEmpty {
            Section {
                ForEach(stops) { stop in
                    Button {
                        dismiss()
                        onShow(stop)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.fontName(stop.name))
                                Text(detail(stop)).font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
                        }
                        .frame(minHeight: 44)
                        .accessibilityHint(L10n.t("mission.open"))
                    }
                    .foregroundStyle(.primary)
                }
                Button {
                    dismiss()
                    onShowRound(stops)
                } label: {
                    Label(L10n.t("gpxIn.showMap"), systemImage: "map").frame(minHeight: 44)
                }
            } header: {
                Label(L10n.t(title), systemImage: icon)
            } footer: {
                Text("\(L10n.t(hint)) · \(L10n.t("mission.radius", ["n": Int(km)]))")
            }
        }
    }

    private func detail(_ stop: MissionTarget) -> String {
        let distance = Measurement(value: stop.distanceKm, unit: UnitLength.kilometers)
            .formatted(.measurement(width: .abbreviated, usage: .road))
        guard let last = stop.lastCheck else { return "\(distance) · \(L10n.t("zones.neverChecked"))" }
        return "\(distance) · \(RelativeTime.string(since: last))"
    }

    private func load() async {
        guard let here = location.location else { state = .idle; return }
        state = .loading
        do {
            state = .loaded(try await APIClient.shared.missions(latitude: here.coordinate.latitude,
                                                                longitude: here.coordinate.longitude))
        } catch {
            state = .failed
        }
    }
}
