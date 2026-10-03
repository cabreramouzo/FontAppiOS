import MapLibre
import SwiftUI
import TipKit

/// The buttons over the map, laid out like Apple Maps: a grouped glass column at the top
/// right and the one primary action (add a fountain) at the bottom right, where the thumb
/// is. Search is its own tab.
///
/// The web had nine floating buttons; here they are fewer and grouped, because on a phone
/// every button covers the map, which is the thing being looked at. The colour legend has
/// its own button: the colours are the first thing seen, and nobody opens "Filters" to
/// learn what grey means. It is also in the filters sheet, next to what it explains.
struct MapControlColumn: View {
    let controller: MapController
    let activeFilters: Int
    let onLayers: () -> Void
    let onFilters: () -> Void
    let legendOpen: Bool
    let onLegend: () -> Void
    var onMissions: (() -> Void)?
    var onOffline: (() -> Void)?
    var onImportGPX: (() -> Void)?
    var onExportGPX: (() -> Void)?
    let staff: Bool

    @State private var gpxTip = GPXTip()
    @State private var gpxTipPending = true

    var body: some View {
        VStack(spacing: 12) {
            GlassEffectContainer {
                VStack(spacing: 0) {
                    ColumnButton(systemImage: "square.3.layers.3d", label: L10n.t("map.layers"), action: onLayers)
                        .mapHelpTarget(.layers)
                    Divider().frame(width: 28)
                    ColumnButton(systemImage: "line.3.horizontal.decrease", label: L10n.t("map.filters"),
                                 badge: activeFilters, action: onFilters)
                        .mapHelpTarget(.filters)
                    Divider().frame(width: 28)
                    // Same gesture as the web: the palette turns into a cross while open.
                    ColumnButton(systemImage: legendOpen ? "xmark" : "paintpalette",
                                 label: L10n.t(legendOpen ? "legend.hide" : "legend.show"), action: onLegend)
                        .mapHelpTarget(.legend)
                    if let onMissions {
                        Divider().frame(width: 28)
                        ColumnButton(systemImage: "figure.walk", label: L10n.t("mission.title"), action: onMissions)
                            .mapHelpTarget(.missions)
                    }
                    if let onOffline {
                        Divider().frame(width: 28)
                        ColumnButton(systemImage: "arrow.down.circle", label: L10n.t("ios.offline.title"), action: onOffline)
                            .mapHelpTarget(.offline)
                    }
                    if let onImportGPX, let onExportGPX {
                        Divider().frame(width: 28)
                        // The first tap shows what the two choices do, with them on the tip;
                        // from then on it is the plain menu.
                        Group {
                            if gpxTipPending {
                                Button {
                                    Task { await GPXTip.tapped.donate() }
                                } label: { gpxLabel }
                                .popoverTip(gpxTip) { action in
                                    gpxTip.invalidate(reason: .actionPerformed)
                                    // After the popover has gone: a file picker asked for while
                                    // it is still on screen is silently dropped (field test).
                                    let run = action.id == GPXTip.import_ ? onImportGPX : onExportGPX
                                    Task {
                                        try? await Task.sleep(for: .milliseconds(450))
                                        run()
                                    }
                                }
                                .tipViewStyle(RoomyTipStyle())
                                .accessibilityLabel("GPX")
                            } else {
                                Menu {
                                    Button(L10n.t("ios.gpx.import"), systemImage: "square.and.arrow.down", action: onImportGPX)
                                    Button(L10n.t("ios.gpx.export"), systemImage: "square.and.arrow.up", action: onExportGPX)
                                } label: { gpxLabel }
                                .accessibilityLabel("GPX")
                            }
                        }
                        .mapHelpTarget(.gpx)
                    }
                }
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 24))
            }
            SystemMapButtons(controller: controller)
        }
        .foregroundStyle(staff ? Color.staff : Color.primary)
        .task {
            for await status in gpxTip.statusUpdates {
                if case .invalidated = status { gpxTipPending = false } else { gpxTipPending = true }
            }
        }
    }

    // Letters, not an icon: whoever carries a GPS unit on the handlebars reads "GPX" at
    // once (web decision, see CLAUDE.md).
    private var gpxLabel: some View {
        Text("GPX")
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .frame(width: 48, height: 48)
            .contentShape(Rectangle())
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

/// Location, drawn in glass like the rest, with the map's three tracking modes. The
/// compass is MapLibre's own, which hides itself when north is up.
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
            .glassButton(in: Circle())
            .accessibilityLabel(L10n.t("map.recenter"))
            .mapHelpTarget(.location)
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
        .glassButton(.regular.tint(staff ? Color.staff : Color.accentColor), in: Circle())
        .accessibilityLabel(L10n.plain("map.addFont"))
    }
}
