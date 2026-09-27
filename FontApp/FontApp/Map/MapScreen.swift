import MapKit
import SwiftUI

struct MapScreen: View {
    @Environment(LocationService.self) private var location
    @Environment(SessionStore.self) private var session
    @State private var model = MapModel()
    @State private var controller = MapController()
    @State private var filters = MapFilters()
    @State private var sheet: MapSheet?

    private enum MapSheet: String, Identifiable {
        case layers, filters, search, offline
        var id: String { rawValue }
    }
    @State private var selected: FontSummary?
    @State private var followRequest = 0
    @State private var didAutoLocate = false

    var body: some View {
        FontMapView(
            fonts: filters.apply(model.fonts),
            clusters: model.clusters,
            initialRegion: { size in
                DefaultMapView.forTimeZone(TimeZone.current.identifier).region(for: size)
            },
            showsUser: location.isAuthorized,
            followRequest: followRequest,
            onMove: { region, size, following in
                model.mapDidMove(region: region, size: size, following: following)
            },
            onSelect: { selected = $0 },
            controller: controller
        )
        .ignoresSafeArea(edges: [.top, .bottom])
        .overlay(alignment: .topTrailing) {
            MapControlColumn(controller: controller, activeFilters: filters.activeCount,
                             onLayers: { sheet = .layers }, onFilters: { sheet = .filters },
                             onOffline: { sheet = .offline },
                             staff: session.isStaff)
                .padding(.trailing, 12)
                .padding(.top, 8)
        }
        .overlay(alignment: .topLeading) {
            MapSearchCapsule { sheet = .search }
                .padding(.leading, 12)
                .padding(.trailing, 76)
                .padding(.top, 8)
        }
        .overlay(alignment: .top) { banner.padding(.trailing, 72).padding(.top, 56) }
        .overlay(alignment: .bottomLeading) { attribution }
        .sheet(item: $sheet) { which in
            switch which {
            case .layers:
                LayersSheet(controller: controller).presentationDetents([.medium, .large])
            case .filters:
                FiltersSheet(filters: $filters).presentationDetents([.medium, .large])
            case .offline:
                OfflineZonesSheet(controller: controller).presentationDetents([.medium, .large])
            case .search:
                SearchScreen(
                    onFountain: { font in
                        controller.show(CLLocationCoordinate2D(latitude: font.latitude, longitude: font.longitude),
                                        meters: 400, aboveSheet: true)
                        selected = font
                    },
                    onPlace: { controller.show($0) }
                )
            }
        }
        .onAppear(perform: locateOnce)
        .onChange(of: location.isAuthorized) { locateOnce() }
        .onReceive(NotificationCenter.default.publisher(for: .fontChanged)) { _ in model.refresh() }
        .sheet(item: $selected) { font in
            NavigationStack {
                FontDetailView(fontID: font.id, preview: font)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(role: .close) { selected = nil }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
    }

    /// Opening the app centres on the user once, as the web does. A refusal leaves the
    /// time-zone view in place.
    private func locateOnce() {
        location.requestIfNeeded()
        guard location.isAuthorized, !didAutoLocate else { return }
        didAutoLocate = true
        followRequest += 1
    }

    @ViewBuilder private var banner: some View {
        if let until = model.rateLimitedUntil, until > .now {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t("map.rateLimited")).font(.subheadline.bold())
                Text(L10n.t("map.rateLimitedBody")).font(.footnote)
            }
            .bannerStyle()
        } else if let message = model.errorMessage {
            Text(message).font(.subheadline).bannerStyle()
        } else if model.isLoading {
            ProgressView()
                .padding(10)
                .background(.regularMaterial, in: Capsule())
                .padding(.top, 8)
                .accessibilityLabel(L10n.t("map.loading"))
        }
    }

    /// The fountains come from OpenStreetMap and ICGC/ACA; both licences require credit
    /// on the map itself, and so does the base map when it is not Apple's (Apple credits
    /// its own).
    private var attribution: some View {
        Text([controller.layer.attribution, L10n.t("ios.dataAttribution")].compactMap { $0 }.joined(separator: "\n"))
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 4))
            .padding(.leading, 8)
            .padding(.bottom, 30)
    }
}

private extension View {
    func bannerStyle() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
            .padding(.top, 8)
    }
}
