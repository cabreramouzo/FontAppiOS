import MapKit
import MapLibre
import PhotosUI
import SwiftUI

/// Adding a fountain. The position is set on a map with a fixed centre pin (the map moves
/// under it, as in Apple Maps), which is precise with a thumb where dragging a pin is not.
struct NewFontSheet: View {
    @State var model: NewFontModel
    let layer: MapLayer
    /// The fountain as created, or nil when it waits in the outbox.
    let onDone: (_ created: FontSummary?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(LocationService.self) private var location
    @Environment(SessionStore.self) private var session
    @State private var showsCamera = false
    @State private var confirmsDiscard = false
    @State private var placesFullScreen = false
    @State private var help: LegendHelp.Kind?
    @State private var exemption: ExemptionState = .idle

    enum ExemptionState { case idle, sending, sent }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PlacementMap(pin: $model.pin, layer: layer)
                        .frame(height: 240)
                        .listRowInsets(EdgeInsets())
                    // A thumb needs room to place a pin: the whole screen, on demand. Its own
                    // row, not over the map, whose pan swallowed a finger that moved a little.
                    Button { placesFullScreen = true } label: {
                        Label(L10n.t("ios.newFont.bigMap"), systemImage: "arrow.up.left.and.arrow.down.right")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    if let km = NewFontPlacement.remoteKm(pin: model.pin, me: location.location) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.t("newFont.remoteTitle", ["distance": km.formatted(.number.precision(.fractionLength(1)))]))
                                .font(.subheadline.weight(.semibold))
                            Text(L10n.t("newFont.remoteBody")).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    if let there = model.photoPosition {
                        Button {
                            model.pin = there
                        } label: {
                            Label(L10n.t("newFont.photoHasGps") + " " + L10n.t("newFont.usePhotoGps"), systemImage: "location")
                        }
                    }
                } footer: {
                    Text(L10n.t("ios.newFont.moveMap"))
                }

                Section {
                    TextField(L10n.t("newFont.nameOpt"), text: $model.draft.name)
                        .textInputAutocapitalization(.words)
                    HStack {
                        Picker(L10n.t("detail.type").trimmingCharacters(in: CharacterSet(charactersIn: ": ")),
                               selection: $model.draft.source) {
                            Text(L10n.t("detail.unknownType")).tag(WaterSource?.none)
                            ForEach(LegendHelp.sources, id: \.self) {
                                Text($0.emojiLabel).tag(WaterSource?.some($0))
                            }
                        }
                        helpButton(.source)
                    }
                    HStack {
                        Picker(L10n.t("detail.drinkability").trimmingCharacters(in: CharacterSet(charactersIn: ": ")),
                               selection: $model.draft.drinkable) {
                            Text(L10n.t("detail.unknownDrink")).tag(Drinkable?.none)
                            ForEach(LegendHelp.drinkables, id: \.self) {
                                Text($0.emojiLabel).tag(Drinkable?.some($0))
                            }
                        }
                        helpButton(.drinkable)
                    }
                    TextField(L10n.t("newFont.descriptionOpt"), text: $model.draft.description, axis: .vertical)
                        .lineLimit(2...5)
                }

                Section {
                    // Every status, as the web offers here, and optional: a fountain can be
                    // added without knowing how it flows today.
                    Picker(L10n.t("popup.howIsIt"), selection: $model.draft.status) {
                        Text("—").tag(String?.none)
                        ForEach(WaterStatus.allCases, id: \.self) {
                            Text("\($0.emoji) \(L10n.t($0.labelKey))").tag(String?.some($0.rawValue))
                        }
                    }
                }

                Section {
                    photoRow
                }

                if case .failed(let message) = model.state {
                    Section {
                        Text(message).foregroundStyle(.red)
                        // Past a new account's daily limit: ask for it to be lifted.
                        if model.limitReached {
                            Button(L10n.t(exemption == .sent ? "sourceLimit.requested"
                                          : exemption == .sending ? "sourceLimit.requesting" : "sourceLimit.request")) {
                                requestExemption()
                            }
                            .disabled(exemption != .idle)
                            .frame(minHeight: 44)
                        }
                    }
                }

                Section {
                    Button(L10n.t("draft.discard"), role: .destructive) { confirmsDiscard = true }
                        .frame(minHeight: 44)
                        .confirmsDestructive(L10n.t("draft.discard"), isPresented: $confirmsDiscard,
                                             action: L10n.t("draft.discard")) {
                            model.discard()
                            dismiss()
                        }
                }
            }
            .navigationTitle(L10n.t("newFont.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // Closing keeps the draft; discarding is its own, confirmed action.
                    Button(role: .close) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isBusy {
                        ProgressView()
                    } else {
                        // In words, as on the web: a bare tick does not say it publishes.
                        Button(L10n.t("form.create")) {
                            Task { await model.submit() }
                        }
                        .buttonStyle(.glassProminent)
                        .tint(session.isStaff ? Color.staff : .accentColor)
                    }
                }
            }
            .alert(duplicateTitle, isPresented: duplicateBinding) {
                Button(L10n.t("ios.newFont.itIsDifferent")) { Task { await model.confirmDistinct() } }
                Button(L10n.t("remote.cancel"), role: .cancel) { model.cancelDuplicate() }
            }
            .fullScreenCover(isPresented: $showsCamera) {
                CameraPicker { jpeg in
                    showsCamera = false
                    guard let jpeg else { return }
                    Task { await usePhoto(jpeg, fromCamera: true) }
                }
                .ignoresSafeArea()
            }
            .onChange(of: model.state) { _, state in
                switch state {
                case .created(let font): onDone(font); dismiss()
                case .queued: onDone(nil); dismiss()
                default: break
                }
            }
            .interactiveDismissDisabled(isBusy)
            // The exact spot, not the map's 100 m: the pin starts on the person.
            .onAppear {
                location.beginPrecise()
                if let fix = location.location { model.userMoved(to: fix) }
            }
            .onDisappear { location.endPrecise() }
            .onChange(of: location.location) { _, fix in
                if let fix { model.userMoved(to: fix) }
            }
            .sheet(item: $help) { kind in
                // Reading what each one means is when people decide: tapping it chooses it.
                switch kind {
                case .source:
                    LegendHelp(kind: kind, selectedSource: model.draft.source) { model.draft.source = $0 }
                case .drinkable:
                    LegendHelp(kind: kind, selectedDrinkable: model.draft.drinkable) { model.draft.drinkable = $0 }
                }
            }
            .fullScreenCover(isPresented: $placesFullScreen) {
                PlacementScreen(pin: $model.pin, layer: layer)
            }
        }
    }

    private var photoRow: some View {
        PhotoSlot(jpeg: model.photo?.jpeg,
                  canTakePhoto: UIImagePickerController.isSourceTypeAvailable(.camera),
                  onTakePhoto: { showsCamera = true },
                  onChosen: { await usePhoto($0, fromCamera: false) },
                  onRemove: { model.photo = nil })
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
    }

    /// Compressed now, with its EXIF read first, so it is ready both to upload and to queue.
    @discardableResult
    private func usePhoto(_ data: Data, fromCamera: Bool) async -> Bool {
        guard var prepared = try? await Task.detached(priority: .userInitiated, operation: {
            try PhotoPreparer.prepare(data)
        }).value else { return false }
        if fromCamera {
            // The camera hands over pixels without EXIF; the facts are known.
            var meta = PhotoMeta(takenAt: .now)
            if location.isAuthorized, let fix = location.location, fix.horizontalAccuracy <= RemoteReview.maxAccuracy {
                meta.latitude = fix.coordinate.latitude
                meta.longitude = fix.coordinate.longitude
            }
            prepared = PhotoPreparer.Prepared(jpeg: prepared.jpeg, meta: meta)
        }
        model.photo = prepared
        return true
    }

    private func helpButton(_ kind: LegendHelp.Kind) -> some View {
        Button { help = kind } label: {
            Image(systemName: "questionmark.circle").imageScale(.large)
        }
        .buttonStyle(.borderless)
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityLabel(L10n.t(kind == .source ? "waterHelp.title" : "drinkHelp.title"))
    }

    private func requestExemption() {
        exemption = .sending
        Task {
            do {
                try await APIClient.shared.requestSourceLimitExemption()
                exemption = .sent
            } catch {
                exemption = .idle
            }
        }
    }

    private var isBusy: Bool {
        model.state == .checking || model.state == .sending
    }

    private var duplicateTitle: String {
        if case .confirmDuplicate(let name, let meters) = model.state {
            return L10n.t("newFont.nearDuplicateNamed", ["m": meters, "name": name])
        }
        return ""
    }

    private var duplicateBinding: Binding<Bool> {
        Binding(get: { if case .confirmDuplicate = model.state { true } else { false } },
                set: { if !$0, case .confirmDuplicate = model.state { model.cancelDuplicate() } })
    }
}

/// A small map with a pin fixed at its centre: moving the map moves the position. Same
/// base map as the main one, so the ICGC or IGN detail used to find the spot is there.
struct PlacementMap: UIViewRepresentable {
    @Binding var pin: CLLocationCoordinate2D
    let layer: MapLayer
    /// The position read when the parent draws: reading it through the binding inside
    /// updateUIView is not observed, so a pin moved from outside (the big map, the
    /// photo's GPS) never redrew this map.
    private let wanted: CLLocationCoordinate2D

    init(pin: Binding<CLLocationCoordinate2D>, layer: MapLayer) {
        _pin = pin
        self.layer = layer
        wanted = pin.wrappedValue
    }

    func makeCoordinator() -> Coordinator { Coordinator(pin: $pin) }

    /// The pin tip on the centre, with a shadow dot marking the exact spot while it is
    /// lifted — the way Apple Maps shows a dropped pin being moved.

    func makeUIView(context: Context) -> MLNMapView {
        let map = MLNMapView(frame: .zero, styleURL: layer.styleURL)
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.allowsRotating = false
        map.allowsTilting = false
        map.logoView.isHidden = true
        map.attributionButton.isHidden = true
        map.setCenter(pin, zoomLevel: 17, animated: false)
        // The same balloon the map raises for a selected fountain: big enough to see
        // under a thumb, with a sharp tip on the exact spot.
        let marker = PinBalloon(color: UIColor(Color.staff))
        marker.translatesAutoresizingMaskIntoConstraints = false
        marker.isAccessibilityElement = false
        marker.layer.anchorPoint = CGPoint(x: 0.5, y: 1)
        let spot = UIView()
        spot.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        spot.layer.cornerRadius = 4
        spot.translatesAutoresizingMaskIntoConstraints = false
        spot.alpha = 0
        map.addSubview(spot)
        map.addSubview(marker)
        NSLayoutConstraint.activate([
            marker.centerXAnchor.constraint(equalTo: map.centerXAnchor),
            // The tip of the pin on the centre (anchor at the bottom moves the frame down
            // by half its height, so the constraint compensates).
            marker.centerYAnchor.constraint(equalTo: map.centerYAnchor),
            spot.centerXAnchor.constraint(equalTo: map.centerXAnchor),
            spot.centerYAnchor.constraint(equalTo: map.centerYAnchor),
            spot.widthAnchor.constraint(equalToConstant: 8),
            spot.heightAnchor.constraint(equalToConstant: 8),
        ])
        context.coordinator.marker = marker
        context.coordinator.spot = spot
        return map
    }

    func updateUIView(_ map: MLNMapView, context: Context) {
        // The photo's GPS button moves the pin from outside.
        let current = map.centerCoordinate
        if abs(current.latitude - wanted.latitude) > 1e-6 || abs(current.longitude - wanted.longitude) > 1e-6 {
            map.setCenter(wanted, animated: true)
        }
    }

    final class Coordinator: NSObject, MLNMapViewDelegate {
        let pin: Binding<CLLocationCoordinate2D>
        weak var marker: UIView?
        weak var spot: UIView?
        private var lifted = false

        init(pin: Binding<CLLocationCoordinate2D>) { self.pin = pin }

        /// Picked up while the map moves under it; the dot shows exactly where it will land.
        func mapView(_ map: MLNMapView, regionWillChangeWith reason: MLNCameraChangeReason, animated: Bool) {
            guard !reason.isEmpty, !reason.contains(.programmatic), !lifted else { return }
            lifted = true
            let reduce = UIAccessibility.isReduceMotionEnabled
            UIView.animate(withDuration: 0.18) {
                self.marker?.transform = reduce ? .identity : CGAffineTransform(translationX: 0, y: -14).scaledBy(x: 1.1, y: 1.1)
                self.spot?.alpha = 1
            }
        }

        func mapView(_ map: MLNMapView, regionDidChangeAnimated animated: Bool) {
            pin.wrappedValue = map.centerCoordinate
            guard lifted else { return }
            lifted = false
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.45, initialSpringVelocity: 0.6) {
                self.marker?.transform = .identity
                self.spot?.alpha = 0
            }
        }
    }
}

/// Placing the pin with the whole screen: the map, the pin at its centre, a button to
/// go to where you are, and Done. The small map in the form follows what is chosen here.
struct PlacementScreen: View {
    @Binding var pin: CLLocationCoordinate2D
    let layer: MapLayer

    @Environment(\.dismiss) private var dismiss
    @Environment(LocationService.self) private var location
    @State private var working: CLLocationCoordinate2D

    init(pin: Binding<CLLocationCoordinate2D>, layer: MapLayer) {
        _pin = pin
        self.layer = layer
        _working = State(initialValue: pin.wrappedValue)
    }

    var body: some View {
        // System bars, not buttons drawn over the map: the map's own gestures took the
        // touches of a finger that moved a little, and the close button sat by the island.
        NavigationStack {
            PlacementMap(pin: $working, layer: layer)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(L10n.t("newFont.title"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { dismiss() } label: { Image(systemName: "xmark") }
                            .accessibilityLabel(L10n.t("ios.close"))
                    }
                    if location.isAuthorized, let here = location.location {
                        ToolbarItem(placement: .primaryAction) {
                            Button { working = here.coordinate } label: { Image(systemName: "location.fill") }
                                .accessibilityLabel(L10n.t("relocate.useMyLocation"))
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: 10) {
                    Text(L10n.t("ios.newFont.moveMap"))
                        .font(.subheadline)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .glassEffect(.regular, in: Capsule())
                    Button {
                        pin = working
                        dismiss()
                    } label: {
                        Text(L10n.t("ios.newFont.placeHere")).font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.glassProminent)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
        }
    }
}

/// What each kind and each drinkability means, as the web's (?) buttons explain it.
struct LegendHelp: View {
    enum Kind: Identifiable { case source, drinkable; var id: Self { self } }
    static let sources: [WaterSource] = [.tap, .mountain, .spring, .well, .fountain, .other]
    /// Most guarantee first: with four options the order is information.
    static let drinkables: [Drinkable] = [.yes, .untreated, .conditional, .no]

    let kind: Kind
    /// With a choice to make (the new fountain's form), each row chooses and closes; the
    /// current one is ticked. Without, the sheet only explains.
    private var selectedSource: WaterSource?
    private var selectedDrinkable: Drinkable?
    private var onSource: ((WaterSource) -> Void)?
    private var onDrinkable: ((Drinkable?) -> Void)?
    @Environment(\.dismiss) private var dismiss

    init(kind: Kind) { self.kind = kind }

    init(kind: Kind, selectedSource: WaterSource?, onSelect: @escaping (WaterSource) -> Void) {
        self.kind = kind
        self.selectedSource = selectedSource
        onSource = onSelect
    }

    init(kind: Kind, selectedDrinkable: Drinkable?, onSelect: @escaping (Drinkable?) -> Void) {
        self.kind = kind
        self.selectedDrinkable = selectedDrinkable
        onDrinkable = onSelect
    }

    var body: some View {
        NavigationStack {
            List {
                switch kind {
                case .source:
                    ForEach(Self.sources, id: \.self) { source in
                        choice(selected: selectedSource == source,
                               action: onSource.map { pick in { pick(source) } }) {
                            row(source.emoji, L10n.t("source.\(source.rawValue)"), L10n.t("waterHelp.\(source.rawValue)"))
                        }
                    }
                case .drinkable:
                    ForEach(Self.drinkables, id: \.self) { drink in
                        choice(selected: selectedDrinkable == drink,
                               action: onDrinkable.map { pick in { pick(drink) } }) {
                            row(drink.emoji, L10n.t("drink.\(drink.rawValue)"), L10n.t("drinkHelp.\(drink.rawValue)"))
                        }
                    }
                    // Not a value, but the one most confused with "untreated"; chosen, it
                    // leaves the field unset — which is what "unknown" is.
                    choice(selected: onDrinkable != nil && selectedDrinkable == nil,
                           action: onDrinkable.map { pick in { pick(nil) } }) {
                        row("❔", L10n.t("detail.unknownDrink"), L10n.t("drinkHelp.unknown"))
                    }
                    Text(L10n.t("drinkHelp.note")).font(.footnote).italic().foregroundStyle(.secondary)
                }
            }
            .navigationTitle(L10n.t(kind == .source ? "waterHelp.title" : "drinkHelp.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(role: .close) { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func choice(selected: Bool, action: (() -> Void)?, @ViewBuilder label: () -> some View) -> some View {
        if let action {
            Button {
                action()
                dismiss()
            } label: {
                HStack {
                    label()
                    Spacer(minLength: 8)
                    if selected {
                        Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(.tint)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
        } else {
            label()
        }
    }

    private func row(_ emoji: String, _ label: String, _ about: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(emoji).font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.headline)
                Text(about).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// A balloon pin: a round head with the drop and a tail ending in a point, 52 pt tall.
final class PinBalloon: UIView {
    init(color: UIColor, head size: CGFloat = 40) {
        let tailHeight: CGFloat = 12
        super.init(frame: CGRect(x: 0, y: 0, width: size, height: size + tailHeight))
        let tail = CAShapeLayer()
        let path = UIBezierPath()
        path.move(to: CGPoint(x: size / 2 - 8, y: size - 6))
        path.addLine(to: CGPoint(x: size / 2, y: size + tailHeight))
        path.addLine(to: CGPoint(x: size / 2 + 8, y: size - 6))
        path.close()
        tail.path = path.cgPath
        tail.fillColor = color.cgColor
        layer.addSublayer(tail)
        let head = UIView(frame: CGRect(x: 0, y: 0, width: size, height: size))
        head.backgroundColor = color
        head.layer.cornerRadius = size / 2
        head.layer.borderColor = UIColor.white.cgColor
        head.layer.borderWidth = 3
        addSubview(head)
        let glyph = UIImageView(image: UIImage(systemName: "drop.fill",
                                               withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .bold)))
        glyph.tintColor = .white
        glyph.contentMode = .center
        glyph.frame = head.bounds
        head.addSubview(glyph)
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.3
        layer.shadowRadius = 4
        layer.shadowOffset = CGSize(width: 0, height: 3)
        widthAnchor.constraint(equalToConstant: size).isActive = true
        heightAnchor.constraint(equalToConstant: size + tailHeight).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("not coded") }
}
