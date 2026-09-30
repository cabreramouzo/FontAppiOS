import MapKit
import MapLibre
import SwiftUI
import UniformTypeIdentifiers

struct MapScreen: View {
    @Environment(LocationService.self) private var location
    @Environment(SessionStore.self) private var session
    @State private var model = MapModel()
    @State private var showsLoading = false
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
    @State private var sheetHandle = SheetHandle()
    /// Whether the open fountain came from a pin, and so can be swiped from.
    @State private var browsing = false
    @State private var followRequest = 0
    @State private var didAutoLocate = false
    @State private var helpTarget: MapHelpTarget?

    var body: some View {
        FontMapView(
            fonts: filters.apply(model.fonts, keep: model.isJustCreated),
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
            onSelect: { font in
                browsing = true
                selected = font
                // The pin into the part of the map the short card leaves in view.
                controller.reveal(CLLocationCoordinate2D(latitude: font.latitude, longitude: font.longitude),
                                  covered: PresentationDetent.shortCardHeight)
            },
            controller: controller,
            route: route?.coordinates ?? [],
            selected: selected
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
        .overlay(alignment: .topLeading) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { helpTarget = .layers }
            } label: {
                Image(systemName: "questionmark")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 48, height: 48)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: Circle())
            .accessibilityLabel(L10n.t("ios.mapHelp.title"))
            .padding(.leading, 12)
            .padding(.top, 8)
        }
        .overlay(alignment: .top) {
            // What waits to be sent and whether there is signal, above the map's own notices.
            VStack(spacing: 0) {
                ConnectivityNoticeView(serverUnavailable: model.serverUnavailable) { showsSignIn = true }
                banner
            }
            .padding(.trailing, 72)
        }
        .overlay(alignment: .top) { loadingPill }
        .animation(.easeInOut(duration: 0.25), value: showsLoading)
        // Only a load that lasts: most answer in a fraction of a second.
        .task(id: model.isLoading) {
            guard model.isLoading else { showsLoading = false; return }
            try? await Task.sleep(for: .milliseconds(700))
            if !Task.isCancelled, model.isLoading { showsLoading = true }
        }
        .overlay(alignment: .bottomLeading) { attribution }
        .overlay(alignment: .bottomTrailing) {
            AddFountainButton(staff: session.isStaff, action: startNewFont)
                .mapHelpTarget(.add)
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
        .overlayPreferenceValue(MapHelpFrames.self) { frames in
            if let helpTarget, let frame = frames[helpTarget] {
                MapHelpOverlay(target: helpTarget, globalFrame: frame) {
                    withAnimation(.easeInOut(duration: 0.2)) { self.helpTarget = helpTarget.next }
                } onClose: {
                    withAnimation(.easeInOut(duration: 0.2)) { self.helpTarget = nil }
                }
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
                    show(toast: L10n.t(created != nil ? "toast.fontCreated" : "offline.savedFont"))
                    if let created { showCreated(created) }
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
        // Deleted: off the map before the reload answers, and its card closed.
        .onReceive(NotificationCenter.default.publisher(for: .fontDeleted)) { note in
            guard let id = note.object as? UUID else { return }
            model.remove(deleted: id)
            if selected?.id == id { selected = nil }
        }
        // One presentation for as long as a fountain is chosen: `.sheet(item:)` swapped
        // the sheet on every new pin and UIKit kept (or grew to) the old height.
        .sheet(isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } })) {
            if let font = selected {
                FountainSheet(font: font, detent: $detent, handle: sheetHandle,
                              neighbours: browsing ? neighbours(of: font) : nil,
                              onBrowse: step, onClose: { selected = nil }) { font in
                    controller.show(CLLocationCoordinate2D(latitude: font.latitude, longitude: font.longitude),
                                    meters: 250, aboveSheet: true)
                }
            }
        }
        // Another pin chosen: back to the short card, as the first one opened, even if
        // the sheet had been lifted. The page grows only when the person lifts it.
        .onChange(of: selected?.id) { old, new in
            if new == nil { browsing = false }
            guard FountainSheetPolicy.lowersOnSelection(from: old, to: new) else { return }
            detent = .shortCard
            sheetHandle.lowerToSmallest()
        }
    }

    /// The nearest fountain on each side of the current one, among those on the map.
    private func neighbours(of font: FontSummary) -> Neighbours {
        let fonts = filters.apply(model.fonts, keep: model.isJustCreated)
        let band = controller.visibleLatitudes(covered: PresentationDetent.shortCardHeight)
        return Neighbours(west: NearbyBrowse.neighbour(of: font, on: .west, among: fonts, latitudes: band),
                          east: NearbyBrowse.neighbour(of: font, on: .east, among: fonts, latitudes: band),
                          from: font)
    }

    /// To that side: the map glides to it, the sheet stays the short card and the pin
    /// rises as when tapped. The line then goes through the new one.
    private func step(_ side: NearbyBrowse.Side) {
        guard let current = selected,
              let font = NearbyBrowse.neighbour(of: current, on: side, among: filters.apply(model.fonts, keep: model.isJustCreated),
                                                latitudes: controller.visibleLatitudes(covered: PresentationDetent.shortCardHeight))
        else { return }
        selected = font
        controller.center(CLLocationCoordinate2D(latitude: font.latitude, longitude: font.longitude),
                          covered: PresentationDetent.shortCardHeight)
    }

    private func showFocus() {
        guard let target = focus?.target else { return }
        focus = nil
        switch target {
        case .fountain(let font):
            controller.show(CLLocationCoordinate2D(latitude: font.latitude, longitude: font.longitude),
                            meters: 400, aboveSheet: true)
            browsing = false
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
        // A half-filled form comes back as it was left, pin included. One with nothing
        // written is not a draft: its pin would pin every new fountain to the same spot.
        if let draft = NewFontDraft.load(), !draft.isEmpty {
            sheet = .newFont(NewFontModel(draft: draft))
            return
        }
        let center = controller.mapView?.centerCoordinate ?? CLLocationCoordinate2D(latitude: 41.8, longitude: 2.1)
        let start = NewFontPlacement.start(mapCenter: center, me: location.isAuthorized ? location.location : nil)
        let model = NewFontModel(draft: NewFontDraft(latitude: start.latitude, longitude: start.longitude))
        if location.isAuthorized { model.followUser(from: start) }
        sheet = .newFont(model)
    }

    /// The new fountain, on the map at once and selected: its raised pin stands above
    /// the blue dot, which otherwise covers it — it was created where the person stands.
    private func showCreated(_ font: FontSummary) {
        model.add(created: font)
        Task {
            // After the form's sheet has gone: one sheet at a time.
            try? await Task.sleep(for: .milliseconds(450))
            selected = font
            controller.center(CLLocationCoordinate2D(latitude: font.latitude, longitude: font.longitude),
                              covered: PresentationDetent.shortCardHeight)
        }
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

    /// Centre once when location is already allowed. The location button asks for
    /// permission when tapped, so a fresh launch never interrupts the welcome.
    private func locateOnce() {
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
        }
    }

    /// Loading, said only when it is slow, as Apple Maps and Komoot do: a quick answer
    /// needs no spinner (and the known pins already show at once), and one that flashes
    /// on every pan reads as the app struggling. After a moment, a small pill centred
    /// under the status bar, with words: a bare spinner says nothing about what loads.
    @ViewBuilder private var loadingPill: some View {
        if showsLoading, model.errorMessage == nil, model.rateLimitedUntil == nil, !controller.outsideCoverage {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(L10n.t("map.loading")).font(.footnote.weight(.medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: Capsule())
            .padding(.top, 8)
            .transition(.opacity.combined(with: .move(edge: .top)))
            .accessibilityElement(children: .combine)
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
    static let shortCardHeight: CGFloat = 420
    static let shortCard = PresentationDetent.height(shortCardHeight)
}

extension UTType {
    static let gpx = UTType(importedAs: "com.topografix.gpx", conformingTo: .xml)
}

/// The fountain's page over the map. Its own view, with the height as a binding.
private struct FountainSheet: View {
    let font: FontSummary
    @Binding var detent: PresentationDetent
    let handle: SheetHandle
    let neighbours: Neighbours?
    let onBrowse: (NearbyBrowse.Side) -> Void
    let onClose: () -> Void
    let reveal: (FontSummary) -> Void

    /// How far the card follows the finger sideways, and how far it goes out.
    @State private var dragX: CGFloat = 0
    /// A horizontal swipe is under way: the page's buttons wait.
    @State private var swiping = false
    @State private var width: CGFloat = 400

    var body: some View {
        NavigationStack {
            FontDetailView(fontID: font.id, preview: font, onClose: onClose)
                // A new page per fountain, its own state and scroll.
                .id(font.id)
                // Over the map it brings the fountain into view, close, and lowers the
                // sheet to the short card so the map shows around it.
                .environment(\.showOnMap) { font in
                    detent = .shortCard
                    // Once the sheet was dragged up, SwiftUI changes the selection and
                    // leaves the sheet where it is (seen on iOS 26): UIKit's sheet is told.
                    handle.lowerToSmallest()
                    reveal(font)
                }
                .background(SheetFinder(handle: handle))
                .safeAreaInset(edge: .top, spacing: 0) {
                    if let neighbours, neighbours.isUseful, detent == .shortCard {
                        BrowseBar(neighbours: neighbours, onBrowse: { slide(to: $0) })
                    }
                }
        }
        // Each fountain as its own page: it follows the finger sideways, goes off the edge
        // and the next one comes in from the other side. The sheet itself stays: iOS
        // keeps its glass card however the sheet's background is set, and moving UIKit's
        // sheet view is undone by its own layout.
        // While swiping, nothing under the finger acts: a swipe that starts on a button
        // used to share, star or open it on release.
        .disabled(swiping)
        // A card stepping aside: a little smaller and fainter the farther it goes.
        .scaleEffect(1 - min(abs(dragX) / max(width, 1), 1) * 0.08)
        .opacity(1 - min(abs(dragX) / max(width, 1), 1) * 0.35)
        .offset(x: dragX)
        .clipped()
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width = $0 }
        // On the short card only: lifted, the page is being read or written in.
        .simultaneousGesture(
            DragGesture(minimumDistance: 20)
                .onChanged { value in
                    let dx = value.translation.width, dy = value.translation.height
                    guard detent == .shortCard, neighbours?.isUseful == true, abs(dx) > abs(dy) * 1.5 else { return }
                    swiping = true
                    // Towards a side with nothing there it resists, as a page at the end.
                    let side: NearbyBrowse.Side = dx < 0 ? .east : .west
                    dragX = neighbours?.has(side) == true ? dx : dx / 4
                }
                .onEnded { value in
                    // After the release has reached the buttons, which then ignore it.
                    Task { try? await Task.sleep(for: .milliseconds(150)); swiping = false }
                    guard detent == .shortCard, let neighbours,
                          let side = NearbyBrowse.swipe(dx: value.translation.width, dy: value.translation.height),
                          neighbours.has(side) else {
                        withAnimation(.spring(duration: 0.3)) { dragX = 0 }
                        return
                    }
                    slide(to: side)
                }
        )
        // Opens as the short card: status, the three chips and the way there, with the
        // map still in view. Up for the whole page.
        .presentationDetents([.shortCard, .large], selection: $detent)
        .presentationBackgroundInteraction(.enabled(upThrough: .shortCard))
    }

    /// Out to one side, in from the other with the next fountain.
    private func slide(to side: NearbyBrowse.Side) {
        let out: CGFloat = side == .east ? -width : width
        if UIAccessibility.isReduceMotionEnabled { dragX = 0; onBrowse(side); return }
        withAnimation(.easeIn(duration: 0.16)) { dragX = out } completion: {
            onBrowse(side)
            dragX = -out
            withAnimation(.spring(duration: 0.34, bounce: 0.12)) { dragX = 0 }
        }
    }
}

/// When the fountain's sheet goes back to the short card.
nonisolated enum FountainSheetPolicy {
    /// A different fountain chosen while the sheet is open, or the first one.
    static func lowersOnSelection(from old: UUID?, to new: UUID?) -> Bool {
        new != nil && new != old
    }
}

/// UIKit's sheet behind a SwiftUI sheet, found from inside it. SwiftUI ignores a new
/// detent once the sheet was dragged (seen on iOS 26 and 27): UIKit's sheet is told.
@MainActor final class SheetHandle {
    weak var controller: UISheetPresentationController?
    /// A view inside the sheet, to find it again when the content was replaced.
    weak var probe: UIViewController?

    /// The smallest height that is not the full page: the short card.
    func lowerToSmallest() {
        if controller == nil { controller = probe.flatMap(Self.sheet(above:)) }
        guard let sheet = controller,
              let short = sheet.detents.first(where: { $0.identifier != .large }) else { return }
        guard sheet.selectedDetentIdentifier != short.identifier else { return }
        sheet.animateChanges { sheet.selectedDetentIdentifier = short.identifier }
    }

    /// Up the parents to the one presented as a sheet.
    static func sheet(above start: UIViewController) -> UISheetPresentationController? {
        var current: UIViewController? = start
        while let c = current {
            if c.presentingViewController != nil, let sheet = c.sheetPresentationController { return sheet }
            current = c.parent
        }
        return nil
    }
}

private struct SheetFinder: UIViewControllerRepresentable {
    let handle: SheetHandle

    func makeUIViewController(context: Context) -> UIViewController { Probe(handle: handle) }
    func updateUIViewController(_ controller: UIViewController, context: Context) {}

    final class Probe: UIViewController {
        let handle: SheetHandle
        init(handle: SheetHandle) { self.handle = handle; super.init(nibName: nil, bundle: nil) }
        required init?(coder: NSCoder) { fatalError() }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            handle.probe = self
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            handle.probe = self
            if let sheet = SheetHandle.sheet(above: self) { handle.controller = sheet }
        }
    }
}

/// The nearest fountain on each side of the open one.
struct Neighbours {
    let west: FontSummary?
    let east: FontSummary?
    let from: FontSummary

    var isUseful: Bool { west != nil || east != nil }
    func has(_ side: NearbyBrowse.Side) -> Bool { (side == .east ? east : west) != nil }

    func distance(to font: FontSummary?) -> String? {
        guard let font else { return nil }
        let meters = CLLocation(latitude: from.latitude, longitude: from.longitude)
            .distance(from: CLLocation(latitude: font.latitude, longitude: font.longitude))
        return Measurement(value: meters, unit: UnitLength.meters).formatted(.measurement(width: .abbreviated, usage: .road))
    }
}

/// "‹ 120 m · 80 m ›": which side has a fountain and how far, so the swipe explains
/// itself, and a tap for whoever cannot swipe.
private struct BrowseBar: View {
    let neighbours: Neighbours
    let onBrowse: (NearbyBrowse.Side) -> Void

    var body: some View {
        HStack {
            side(.west)
            Spacer()
            side(.east)
        }
        .font(.footnote.weight(.semibold))
        .padding(.horizontal, 20)
        .padding(.top, 8)
        // The page's own top margin already separates it from the title.
        .padding(.bottom, -14)
        .sensoryFeedback(.selection, trigger: neighbours.from.id)
    }

    @ViewBuilder private func side(_ side: NearbyBrowse.Side) -> some View {
        let font = side == .east ? neighbours.east : neighbours.west
        Button { onBrowse(side) } label: {
            HStack(spacing: 4) {
                if side == .west { Image(systemName: "chevron.left") }
                Text(neighbours.distance(to: font) ?? "").monospacedDigit()
                if side == .east { Image(systemName: "chevron.right") }
            }
            .frame(minWidth: 44, minHeight: 32)
        }
        .buttonStyle(.borderless)
        .opacity(font == nil ? 0 : 1)
        .disabled(font == nil)
        .accessibilityLabel(L10n.t(side == .east ? "ios.browse.next" : "ios.browse.previous"))
    }
}
