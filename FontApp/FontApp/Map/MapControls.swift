import MapKit
import SwiftUI

/// The buttons over the map, laid out like Apple Maps: a search capsule at the top, a
/// grouped glass column at the top right, and the one primary action (add a fountain) at
/// the bottom right, where the thumb is.
///
/// The web had nine floating buttons; here they are fewer and grouped, because on a phone
/// every button covers the map, which is the thing being looked at. The colour legend
/// lives in the filters sheet, next to what it explains.
struct MapControlColumn: View {
    let controller: MapController
    let activeFilters: Int
    let onLayers: () -> Void
    let onFilters: () -> Void
    var onMissions: (() -> Void)?
    var onOffline: (() -> Void)?
    var onImportGPX: (() -> Void)?
    var onExportGPX: (() -> Void)?
    let staff: Bool

    var body: some View {
        VStack(spacing: 12) {
            GlassEffectContainer {
                VStack(spacing: 0) {
                    ColumnButton(systemImage: "square.3.layers.3d", label: L10n.t("map.layers"), action: onLayers)
                    Divider().frame(width: 28)
                    ColumnButton(systemImage: "line.3.horizontal.decrease", label: L10n.t("map.filters"),
                                 badge: activeFilters, action: onFilters)
                    if let onMissions {
                        Divider().frame(width: 28)
                        ColumnButton(systemImage: "figure.walk", label: L10n.t("mission.title"), action: onMissions)
                    }
                    if let onOffline {
                        Divider().frame(width: 28)
                        ColumnButton(systemImage: "arrow.down.circle", label: L10n.t("ios.offline.title"), action: onOffline)
                    }
                    if let onImportGPX, let onExportGPX {
                        Divider().frame(width: 28)
                        Menu {
                            Button(L10n.t("ios.gpx.import"), systemImage: "square.and.arrow.down", action: onImportGPX)
                            Button(L10n.t("ios.gpx.export"), systemImage: "square.and.arrow.up", action: onExportGPX)
                        } label: {
                            // Letters, not an icon: whoever carries a GPS unit on the
                            // handlebars reads "GPX" at once (web decision, see CLAUDE.md).
                            Text("GPX")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .frame(width: 48, height: 48)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("GPX")
                    }
                }
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 24))
            }
            SystemMapButtons(controller: controller)
        }
        .foregroundStyle(staff ? Color.staff : Color.primary)
    }
}

private struct ColumnButton: View {
    let systemImage: String
    let label: String
    var badge = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
                .overlay(alignment: .topTrailing) {
                    if badge > 0 {
                        Text("\(badge)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(Color.accentColor, in: Circle())
                            .offset(x: -6, y: 6)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(badge > 0 ? "\(badge)" : "")
    }
}

/// Location and compass. Location is drawn here, in glass like the rest, with MapKit's
/// three modes; the compass is MapKit's own, which hides itself when north is up.
private struct SystemMapButtons: View {
    let controller: MapController
    @Environment(LocationService.self) private var location

    var body: some View {
        VStack(spacing: 12) {
            Button {
                if location.isAuthorized {
                    controller.cycleTracking()
                } else {
                    location.requestIfNeeded()
                }
            } label: {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 48, height: 48)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: Circle())
            .accessibilityLabel(L10n.t("map.recenter"))
            MapKitButton(controller: controller, generation: controller.generation) { map in
                let compass = MKCompassButton(mapView: map)
                compass.compassVisibility = .adaptive
                return compass
            }
            .frame(width: 48, height: 48)
        }
    }

    private var icon: String {
        switch controller.trackingMode {
        case .follow: "location.fill"
        case .followWithHeading: "location.north.line.fill"
        default: "location"
        }
    }
}

private struct MapKitButton: UIViewRepresentable {
    let controller: MapController
    /// Rebuilds the button once the map view exists.
    let generation: Int
    let make: (MKMapView) -> UIView

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .clear
        install(in: container)
        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        if container.subviews.isEmpty { install(in: container) }
    }

    private func install(in container: UIView) {
        guard let map = controller.mapView else { return }
        let button = make(map)
        button.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(button)
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            button.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
    }
}

/// "Search a fountain or a place", which opens the full-screen search.
struct MapSearchCapsule: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                Text(L10n.t("ios.search.prompt"))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.body)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .frame(height: 48)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Capsule())
    }
}

/// The one primary action on the map.
struct AddFountainButton: View {
    let staff: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
        }
        .glassEffect(.regular.tint(staff ? Color.staff : Color.accentColor).interactive(), in: Circle())
        .accessibilityLabel(L10n.plain("map.addFont"))
    }
}
