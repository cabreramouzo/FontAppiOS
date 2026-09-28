import MapKit
import MapLibre
import PhotosUI
import SwiftUI

/// Adding a fountain. The position is set on a map with a fixed centre pin (the map moves
/// under it, as in Apple Maps), which is precise with a thumb where dragging a pin is not.
struct NewFontSheet: View {
    @State var model: NewFontModel
    let layer: MapLayer
    let onDone: (_ created: Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(LocationService.self) private var location
    @Environment(SessionStore.self) private var session
    @State private var pickerItem: PhotosPickerItem?
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
                        .overlay(alignment: .topTrailing) {
                            // A thumb needs room to place a pin: the whole screen, on demand.
                            Button { placesFullScreen = true } label: {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.body.weight(.semibold))
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                            .glassEffect(.regular.interactive(), in: Circle())
                            .padding(10)
                            .accessibilityLabel(L10n.t("ios.newFont.bigMap"))
                        }
                        .listRowInsets(EdgeInsets())
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
            .confirmationDialog(L10n.t("draft.discard"), isPresented: $confirmsDiscard) {
                Button(L10n.t("draft.discard"), role: .destructive) {
                    model.discard()
                    dismiss()
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
                if state == .created || state == .queued {
                    onDone(state == .created)
                    dismiss()
                }
            }
            .interactiveDismissDisabled(isBusy)
            .sheet(item: $help) { LegendHelp(kind: $0) }
            .fullScreenCover(isPresented: $placesFullScreen) {
                PlacementScreen(pin: $model.pin, layer: layer)
            }
        }
    }

    @ViewBuilder private var photoRow: some View {
        if let photo = model.photo, let image = UIImage(data: photo.jpeg) {
            HStack {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(width: 72, height: 72).clipShape(RoundedRectangle(cornerRadius: 10))
                Spacer()
                Button(L10n.t("draft.discard"), role: .destructive) { model.photo = nil }
            }
        } else {
            HStack(spacing: 8) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button {
                        showsCamera = true
                    } label: {
                        Label(L10n.t("ios.takePhoto"), systemImage: "camera").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                }
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label(L10n.t("ios.choosePhoto"), systemImage: "photo.on.rectangle").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .onChange(of: pickerItem) { _, item in
                    guard let item else { return }
                    pickerItem = nil
                    Task {
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            await usePhoto(data, fromCamera: false)
                        }
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
        }
    }

    /// Compressed now, with its EXIF read first, so it is ready both to upload and to queue.
    private func usePhoto(_ data: Data, fromCamera: Bool) async {
        guard var prepared = try? await Task.detached(priority: .userInitiated, operation: {
            try PhotoPreparer.prepare(data)
        }).value else { return }
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
        if abs(current.latitude - pin.latitude) > 1e-6 || abs(current.longitude - pin.longitude) > 1e-6 {
            map.setCenter(pin, animated: true)
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
        PlacementMap(pin: $working, layer: layer)
            .ignoresSafeArea()
            .overlay(alignment: .top) {
                Text(L10n.t("ios.newFont.moveMap"))
                    .font(.subheadline)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .glassEffect(.regular, in: Capsule())
                    .padding(.top, 8)
                    .padding(.horizontal, 70)
            }
            .overlay(alignment: .topLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.body.weight(.semibold)).frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: Circle())
                .padding(.leading, 12).padding(.top, 4)
                .accessibilityLabel(L10n.t("ios.close"))
            }
            .overlay(alignment: .bottom) {
                HStack(spacing: 12) {
                    if location.isAuthorized, let here = location.location {
                        Button { working = here.coordinate } label: {
                            Image(systemName: "location.fill").font(.body.weight(.semibold)).frame(width: 52, height: 52)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: Circle())
                        .accessibilityLabel(L10n.t("relocate.useMyLocation"))
                    }
                    Button {
                        pin = working
                        dismiss()
                    } label: {
                        Text(L10n.t("ios.newFont.placeHere")).font(.headline).foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.tint(.accentColor).interactive(), in: Capsule())
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                switch kind {
                case .source:
                    ForEach(Self.sources, id: \.self) { row($0.emoji, L10n.t("source.\($0.rawValue)"), L10n.t("waterHelp.\($0.rawValue)")) }
                case .drinkable:
                    ForEach(Self.drinkables, id: \.self) { row($0.emoji, L10n.t("drink.\($0.rawValue)"), L10n.t("drinkHelp.\($0.rawValue)")) }
                    // Not a value, but the one most confused with "untreated".
                    row("❔", L10n.t("detail.unknownDrink"), L10n.t("drinkHelp.unknown"))
                    Text(L10n.t("drinkHelp.note")).font(.footnote).italic().foregroundStyle(.secondary)
                }
            }
            .navigationTitle(L10n.t(kind == .source ? "waterHelp.title" : "drinkHelp.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(role: .close) { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
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
