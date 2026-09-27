import MapKit
import SwiftUI
import UniformTypeIdentifiers

struct MapScreen: View {
    @Environment(LocationService.self) private var location
    @Environment(SessionStore.self) private var session
    @State private var model = MapModel()
    @State private var controller = MapController()
    @State private var filters = MapFilters()
    @State private var sheet: MapSheet?
    @State private var route: RouteModel?
    @State private var importsGPX = false
    @State private var exported: SharedFile?
    @State private var gpxMessage: String?

    private enum MapSheet: String, Identifiable {
        case layers, filters, search, offline, route
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
            controller: controller,
            route: route?.coordinates ?? []
        )
        .ignoresSafeArea(edges: [.top, .bottom])
        .overlay(alignment: .topTrailing) {
            MapControlColumn(controller: controller, activeFilters: filters.activeCount,
                             onLayers: { sheet = .layers }, onFilters: { sheet = .filters },
                             onOffline: { sheet = .offline },
                             onImportGPX: { if route == nil { importsGPX = true } else { sheet = .route } },
                             onExportGPX: exportVisibleFountains,
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
            case .route:
                if let route {
                    RouteSheet(route: route,
                               onShow: { font in
                                   controller.show(CLLocationCoordinate2D(latitude: font.latitude, longitude: font.longitude),
                                                   meters: 400, aboveSheet: true)
                                   selected = font
                               },
                               onForget: { self.route = nil })
                        .presentationDetents([.medium, .large])
                }
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
        .fileImporter(isPresented: $importsGPX,
                      allowedContentTypes: [.gpx, .xml]) { result in
            openGPX(result)
        }
        .sheet(item: $exported) { ActivityView(items: [$0.url]) }
        .alert(gpxMessage ?? "", isPresented: Binding(get: { gpxMessage != nil }, set: { if !$0 { gpxMessage = nil } })) {
            Button("OK", role: .cancel) {}
        }
        // A .gpx shared from another app (Wikiloc, Mail, AirDrop) opens here.
        .onOpenURL { url in
            if url.isFileURL { openGPX(.success(url)) }
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

    /// Reads the GPX on the phone; the file itself is never sent anywhere.
    private func openGPX(_ result: Result<URL, any Error>) {
        guard case .success(let url) = result else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            gpxMessage = L10n.t("gpxIn.failed")
            return
        }
        let points = GPX.read(data)
        guard points.count >= 2 else {
            gpxMessage = L10n.t("gpxIn.notATrack")
            return
        }
        let model = RouteModel(name: url.deletingPathExtension().lastPathComponent, points: points)
        route = model
        sheet = .route
        Task { await model.load() }
    }

    /// The fountains in view as waypoints for a GPS unit. At most 500, the ones nearest the
    /// centre when there are more, and it says so.
    private func exportVisibleFountains() {
        guard let box = controller.visibleBox else { return }
        Task {
            let fonts: [FontSummary]
            do {
                fonts = try await APIClient.shared.fontsInBounds(box)
            } catch {
                fonts = OfflineZones.shared.fonts(in: box)
            }
            guard !fonts.isEmpty else {
                gpxMessage = L10n.t("gpx.empty")
                return
            }
            let chosen = GPX.nearestToCentre(fonts, of: box)
            let text = GPX.build(chosen.map {
                GPX.Waypoint(latitude: $0.latitude, longitude: $0.longitude, name: L10n.fontName($0.name),
                             description: GPX.description(of: $0))
            })
            if fonts.count > chosen.count {
                gpxMessage = L10n.t("gpx.doneCapped", ["n": chosen.count, "total": fonts.count])
            }
            exported = SharedFile.write(text, name: GPX.fileName())
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

extension UTType {
    static let gpx = UTType(importedAs: "com.topografix.gpx", conformingTo: .xml)
}
