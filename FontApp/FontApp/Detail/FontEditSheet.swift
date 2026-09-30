import CoreLocation
import SwiftUI

struct FontEditSheet: View {
    @State var model: FontEditModel
    let onSaved: (FontDetail) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var session
    @Environment(LocationService.self) private var location
    @State private var showsCamera = false
    @State private var confirmsDiscard = false
    @State private var usedAccuracy: Double?
    @State private var locating = false
    @State private var locationError: String?
    @AppStorage("map.layer") private var layerID = MapLayer.world.rawValue

    @State private var readingPhoto = false
    private var busy: Bool { model.saving || readingPhoto }
    private var layer: MapLayer { MapLayer(rawValue: layerID) ?? .world }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(L10n.t("detail.editInfoNote")).font(.footnote).foregroundStyle(.secondary)
                }
                if !model.ready {
                    Section {
                        if model.error == nil { ProgressView(L10n.t("detail.loading")) }
                        else { Button(L10n.t("activity.retry")) { Task { await model.prepare() } } }
                    }
                }
                if model.ready && !model.permissions.canEdit {
                    Section { Text(L10n.t("cap.blocked.restricted")).foregroundStyle(.orange) }
                }
                Section {
                    TextField(L10n.t("newFont.nameOpt"), text: $model.fields.name)
                        .textInputAutocapitalization(.words)
                    TextField(L10n.t("newFont.descriptionOpt"), text: $model.fields.description, axis: .vertical)
                        .lineLimit(2...6)
                    Picker(label("detail.type"), selection: $model.fields.source) {
                        Text(L10n.t("detail.unknownType")).tag(WaterSource?.none)
                        ForEach([WaterSource.tap, .mountain, .spring, .well, .fountain, .other], id: \.self) {
                            Text($0.emojiLabel).tag(WaterSource?.some($0))
                        }
                    }
                    Picker(label("detail.drinkability"), selection: $model.fields.drinkable) {
                        Text(L10n.t("detail.unknownDrink")).tag(Drinkable?.none)
                        ForEach([Drinkable.yes, .untreated, .conditional, .no], id: \.self) {
                            Text($0.emojiLabel).tag(Drinkable?.some($0))
                        }
                    }
                }
                .disabled(busy || !model.ready || !model.permissions.canEdit)

                if model.ready {
                    locationSection
                    if model.permissions.canSetPhoto {
                        Section(L10n.t(model.original.image == nil ? "detail.addPhoto" : "detail.replacePhoto")) {
                            photoControls
                            if model.original.image == nil {
                                Text(L10n.t("detail.firstPhotoNote")).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        .disabled(busy)
                    }
                }
                if let error = model.error {
                    Section { Text(error).foregroundStyle(.red).accessibilityIdentifier("fontEdit.error") }
                }
            }
            .navigationTitle(L10n.t("detail.editingTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button(L10n.t(model.saving ? "form.saving" : "form.save")) {
                        Task {
                            if let font = await model.save() { onSaved(font); dismiss() }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(session.isStaff ? Color.staff : .accentColor)
                    .disabled(busy || !model.ready || !model.permissions.canEdit || !model.dirty)
                    .accessibilityIdentifier("fontEdit.save")
                    Button(L10n.t("form.discard")) {
                        if model.dirty { confirmsDiscard = true }
                        else { model.discard(); dismiss() }
                    }
                    .disabled(busy)
                    .confirmationDialog(L10n.t("form.discardTitle"), isPresented: $confirmsDiscard,
                                        titleVisibility: .visible) {
                        Button(L10n.t("form.discard"), role: .destructive) { model.discard(); dismiss() }
                        Button(L10n.t("form.keepEditing"), role: .cancel) {}
                    } message: { Text(L10n.t("form.discardBody")) }
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .padding(.horizontal).padding(.vertical, 8)
                .background(.bar)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // Closing keeps the account's draft, as does a swipe dismissal.
                    Button(role: .close) { dismiss() }.disabled(busy)
                }
            }
            .interactiveDismissDisabled(busy)
            .task { await model.prepare() }
            .onChange(of: session.userID) { _, id in
                if id != model.userID { dismiss() }
            }
            .fullScreenCover(isPresented: $showsCamera) {
                CameraPicker { data in
                    showsCamera = false
                    guard let data else { return }
                    var meta = PhotoMeta(takenAt: .now)
                    if location.isAuthorized, let fix = location.location,
                       fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= RemoteReview.maxAccuracy,
                       abs(fix.timestamp.timeIntervalSinceNow) < 180 {
                        meta.latitude = fix.coordinate.latitude
                        meta.longitude = fix.coordinate.longitude
                    }
                    Task { await model.usePhoto(data, cameraMeta: meta) }
                }.ignoresSafeArea()
            }
        }
    }

    private var locationSection: some View {
        Section(L10n.t("relocate.title")) {
            if model.permissions.canRelocate {
                Picker(L10n.t("map.layers"), selection: $layerID) {
                    ForEach(MapLayer.allCases) { Text(L10n.t($0.labelKey)).tag($0.rawValue) }
                }
                PlacementMap(pin: $model.pin, layer: layer)
                    .id(layer)
                    .frame(height: 260)
                    .listRowInsets(EdgeInsets())
                Text(layer.attribution).font(.caption2).foregroundStyle(.secondary)
                Text(L10n.t("ios.newFont.moveMap")).font(.footnote).foregroundStyle(.secondary)
                Button(L10n.t(locating ? "relocate.locating" : "relocate.useMyLocation")) {
                    locationError = nil
                    guard location.authorization != .denied && location.authorization != .restricted else {
                        locationError = L10n.t("map.geoDenied")
                        return
                    }
                    location.requestIfNeeded()
                    locating = true
                    useCurrentLocation()
                }
                .frame(minHeight: 44)
                .onChange(of: location.location) { _, _ in if locating { useCurrentLocation() } }
                .task(id: locating) {
                    guard locating else { return }
                    try? await Task.sleep(for: .seconds(10))
                    if !Task.isCancelled {
                        locating = false
                        locationError = L10n.t("map.geoUnavailable")
                    }
                }
                if let locationError { Text(locationError).font(.footnote).foregroundStyle(.red) }
                if let accuracy = usedAccuracy {
                    Text(L10n.t(accuracy > 25 ? "relocate.poorAccuracy" : "relocate.accuracy",
                                ["m": Int(accuracy.rounded())])).font(.footnote).foregroundStyle(.secondary)
                }
                if model.movedMeters > 1 {
                    Text(L10n.t("relocate.moved", ["d": "\(Int(model.movedMeters.rounded())) m"]))
                    Button(L10n.t("relocate.undo")) {
                        model.pin = .init(latitude: model.original.latitude, longitude: model.original.longitude)
                    }.frame(minHeight: 44)
                }
            } else {
                Text(L10n.t("relocate.notYours")).font(.footnote).foregroundStyle(.secondary)
                if let notice = model.relocationNotice { Text(notice).font(.footnote).foregroundStyle(.secondary) }
                if model.hasRelocation {
                    Button(L10n.t("relocate.undo")) { model.undoRelocation() }.frame(minHeight: 44)
                }
            }
        }
        .disabled(busy)
    }

    @ViewBuilder private var photoControls: some View {
        if model.needsPhotoAgain { Text(L10n.t("draft.photoAgain")).font(.footnote) }
        PhotoSlot(jpeg: model.photo?.jpeg,
                  canTakePhoto: UIImagePickerController.isSourceTypeAvailable(.camera),
                  onTakePhoto: { showsCamera = true },
                  onChosen: { data in
                      await model.usePhoto(data)
                      return model.photo != nil
                  },
                  onRemove: { model.photo = nil },
                  onReadingChanged: { readingPhoto = $0 })
    }

    private func useCurrentLocation() {
        guard location.isAuthorized, let fix = location.location,
              fix.horizontalAccuracy >= 0, abs(fix.timestamp.timeIntervalSinceNow) < 30 else { return }
        model.pin = fix.coordinate
        usedAccuracy = fix.horizontalAccuracy
        locating = false
    }

    private func label(_ key: String) -> String {
        L10n.t(key).trimmingCharacters(in: CharacterSet(charactersIn: ": "))
    }
}
