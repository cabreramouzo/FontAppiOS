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

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PlacementMap(pin: $model.pin, layer: layer)
                        .frame(height: 240)
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
                    Picker(L10n.t("detail.type").trimmingCharacters(in: CharacterSet(charactersIn: ": ")),
                           selection: $model.draft.source) {
                        Text(L10n.t("detail.unknownType")).tag(WaterSource?.none)
                        ForEach([WaterSource.tap, .mountain, .spring, .well, .fountain, .other], id: \.self) {
                            Text($0.emojiLabel).tag(WaterSource?.some($0))
                        }
                    }
                    Picker(L10n.t("detail.drinkability").trimmingCharacters(in: CharacterSet(charactersIn: ": ")),
                           selection: $model.draft.drinkable) {
                        Text(L10n.t("detail.unknownDrink")).tag(Drinkable?.none)
                        ForEach([Drinkable.yes, .untreated, .conditional, .no], id: \.self) {
                            Text($0.emojiLabel).tag(Drinkable?.some($0))
                        }
                    }
                    TextField(L10n.t("newFont.descriptionOpt"), text: $model.draft.description, axis: .vertical)
                        .lineLimit(2...5)
                }

                Section {
                    // The same three as the chips, and optional: a fountain can be added
                    // without knowing how it flows today.
                    Picker(L10n.t("popup.howIsIt"), selection: $model.draft.status) {
                        Text("—").tag(String?.none)
                        ForEach(QuickReviewModel.chips, id: \.self) {
                            Text("\($0.emoji) \(L10n.t($0.labelKey))").tag(String?.some($0.rawValue))
                        }
                    }
                }

                Section {
                    photoRow
                }

                if case .failed(let message) = model.state {
                    Section { Text(message).foregroundStyle(.red) }
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
                        Button(role: .confirm) {
                            Task { await model.submit() }
                        }
                        .tint(session.isStaff ? Color.staff : .accentColor)
                        .accessibilityLabel(L10n.plain("map.addFont"))
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

    func makeUIView(context: Context) -> MLNMapView {
        let map = MLNMapView(frame: .zero, styleURL: layer.styleURL)
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.allowsRotating = false
        map.allowsTilting = false
        map.logoView.isHidden = true
        map.attributionButton.isHidden = true
        map.setCenter(pin, zoomLevel: 17, animated: false)
        let marker = UIImageView(image: UIImage(systemName: "mappin",
                                                withConfiguration: UIImage.SymbolConfiguration(pointSize: 34, weight: .bold)))
        marker.tintColor = UIColor(Color.staff)
        marker.translatesAutoresizingMaskIntoConstraints = false
        marker.isAccessibilityElement = false
        map.addSubview(marker)
        NSLayoutConstraint.activate([
            marker.centerXAnchor.constraint(equalTo: map.centerXAnchor),
            // The tip of the pin on the centre.
            marker.bottomAnchor.constraint(equalTo: map.centerYAnchor),
        ])
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

        init(pin: Binding<CLLocationCoordinate2D>) { self.pin = pin }

        func mapView(_ map: MLNMapView, regionDidChangeAnimated animated: Bool) {
            pin.wrappedValue = map.centerCoordinate
        }
    }
}
