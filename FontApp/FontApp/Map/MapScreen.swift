import MapKit
import MapLibre
import SwiftUI
import UniformTypeIdentifiers

struct MapScreen: View {
    @Environment(LocationService.self) private var location
    @Environment(SessionStore.self) private var session
    @State private var model = MapModel()
    @State private var controller = MapController()
    @State private var filters = MapFilters()
    @State private var sheet: MapSheet?
    /// What the Search tab asked to show; cleared once shown.
    @Binding var focus: MapFocus?
    @State private var route: RouteModel?
    @State private var importsGPX = false
    @State private var exported: SharedFile?
    @State private var gpxMessage: String?
    @State private var showsSignIn = false
    /// "+" was tapped signed out: once signed in, the form opens by itself, which is
    /// what was asked for, instead of leaving the person back on the map.
    @State private var addAfterSignIn = false
    @State private var toast: String?

    private enum MapSheet: Identifiable {
        case layers, filters, offline, missions
        case route(RouteModel)
        /// The model travels with the case: a separate optional state is still nil in the
        /// first render of the sheet, which then shows empty.
        case newFont(NewFontModel)

        var id: String {
            switch self {
            case .layers: "layers"
            case .filters: "filters"
            case .offline: "offline"
            case .missions: "missions"
            case .route: "route"
            case .newFont: "newFont"
            }
        }
    }
    @State private var selected: FontSummary?
    @State private var detent: PresentationDetent = .shortCard
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
                controller.checkCoverage()
            },
            onSelect: { selected = $0 },
            controller: controller,
            route: route?.coordinates ?? []
        )
        .ignoresSafeArea(edges: [.top, .bottom])
        .overlay(alignment: .topTrailing) {
            MapControlColumn(controller: controller, activeFilters: filters.activeCount,
                             onLayers: { sheet = .layers }, onFilters: { sheet = .filters },
                             onMissions: { sheet = .missions },
                             onOffline: { sheet = .offline },
                             onImportGPX: { if let route { sheet = .route(route) } else { importsGPX = true } },
                             onExportGPX: exportVisibleFountains,
                             staff: session.isStaff)
                .padding(.trailing, 12)
                .padding(.top, 8)
        }
        .overlay(alignment: .top) { banner.padding(.trailing, 72) }
        .overlay(alignment: .bottomLeading) { attribution }
        .overlay(alignment: .bottomTrailing) {
            AddFountainButton(staff: session.isStaff, action: startNewFont)
                .padding(.trailing, 16)
                .padding(.bottom, 64)
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(.subheadline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glassEffect(.regular, in: Capsule())
                    .padding(.bottom, 130)
                    .transition(.opacity)
            }
        }
        // A result chosen in the Search tab.
        .onChange(of: focus) { showFocus() }
        .onAppear(perform: showFocus)
        .sheet(isPresented: $showsSignIn, onDismiss: {
            if addAfterSignIn, session.isSignedIn {
                addAfterSignIn = false
                startNewFont()
            } else {
                addAfterSignIn = false
            }
        }) { SignInView() }
        .sheet(item: $sheet) { which in
            switch which {
            case .layers:
                LayersSheet(controller: controller).presentationDetents([.medium, .large])
            case .filters:
                FiltersSheet(filters: $filters).presentationDetents([.medium, .large])
            case .newFont(let model):
                NewFontSheet(model: model, layer: controller.layer) { created in
                    show(toast: L10n.t(created ? "toast.fontCreated" : "offline.savedFont"))
                }
            case .route(let route):
                RouteSheet(route: route,
                           onShow: { font in
                               controller.show(CLLocationCoordinate2D(latitude: font.latitude, longitude: font.longitude),
                                               meters: 400, aboveSheet: true)
                               selected = font
                           },
                           onForget: { self.route = nil })
                    .presentationDetents([.medium, .large])
            case .missions:
                MissionsSheet(
                    onShow: { stop in
                        controller.show(CLLocationCoordinate2D(latitude: stop.latitude, longitude: stop.longitude),
                                        meters: 400, aboveSheet: true)
                        openFountain(stop.id)
                    },
                    onShowRound: { stops in
                        let rect = stops.reduce(MKMapRect.null) {
                            $0.union(MKMapRect(origin: MKMapPoint(CLLocationCoordinate2D(latitude: $1.latitude, longitude: $1.longitude)),
                                               size: MKMapSize(width: 0, height: 0)))
                        }
                        controller.show(rect)
                    })
                    .presentationDetents([.medium, .large])
            case .offline:
                OfflineZonesSheet(controller: controller).presentationDetents([.medium, .large])
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
            // Opens as the short card: status, the three chips and the way there, with the
            // map still in view. Up for the whole page.
            .presentationDetents([.shortCard, .large], selection: $detent)
            .presentationBackgroundInteraction(.enabled(upThrough: .shortCard))
        }
        .onChange(of: selected?.id) { detent = .shortCard }
    }

    private func showFocus() {
        guard let target = focus?.target else { return }
        focus = nil
        switch target {
        case .fountain(let font):
            controller.show(CLLocationCoordinate2D(latitude: font.latitude, longitude: font.longitude),
                            meters: 400, aboveSheet: true)
            selected = font
        case .place(let rect):
            controller.show(rect)
        }
    }

    /// Opens a fountain known only by its id: from the loaded pins if it is one of them.
    private func openFountain(_ id: UUID) {
        if let font = model.fonts.first(where: { $0.id == id }) {
            selected = font
        } else {
            Task {
                if let detail = try? await APIClient.shared.font(id) {
                    selected = FontSummary(detail)
                }
            }
        }
    }

    /// "+" on the map. Without a session there is nothing to add yet: sign in first.
    private func startNewFont() {
        guard session.isSignedIn else {
            addAfterSignIn = true
            showsSignIn = true
            return
        }
        // A half-filled form comes back as it was left, pin included.
        let draft = NewFontDraft.load() ?? {
            let center = controller.mapView?.centerCoordinate ?? CLLocationCoordinate2D(latitude: 41.8, longitude: 2.1)
            let start = NewFontPlacement.start(mapCenter: center, me: location.isAuthorized ? location.location : nil)
            return NewFontDraft(latitude: start.latitude, longitude: start.longitude)
        }()
        sheet = .newFont(NewFontModel(draft: draft))
    }

    private func show(toast text: String) {
        withAnimation { toast = text }
        Task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation { toast = nil }
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
        sheet = .route(model)
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
        } else if controller.outsideCoverage {
            HStack(spacing: 12) {
                Text(L10n.t("ios.layer.outside", ["layer": L10n.t(controller.layer.labelKey)]))
                    .font(.footnote)
                Button(L10n.t("ios.layer.useWorld")) { controller.layer = .world }
                    .font(.footnote.bold())
                    .buttonStyle(.borderedProminent)
                    .frame(minHeight: 44)
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

extension PresentationDetent {
    /// A fountain's short card: title, status line, chips and directions.
    static let shortCard = PresentationDetent.height(420)
}

extension UTType {
    static let gpx = UTType(importedAs: "com.topografix.gpx", conformingTo: .xml)
}
