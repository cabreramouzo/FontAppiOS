import SwiftUI

/// Other photos and documents of a fountain, as the web's gallery: another view, the
/// surroundings, or a document such as the water analysis. The cover stays on the page;
/// this is asked for only when opened.
struct GalleryScreen: View {
    let fontID: UUID

    @Environment(SessionStore.self) private var session
    @State private var photos: [FontPhoto]?
    @State private var error: String?
    @State private var adding = false
    @State private var captioning: FontPhoto?
    @State private var caption = ""
    @State private var removing: FontPhoto?

    /// Its uploader or an admin.
    private func canManage(_ photo: FontPhoto) -> Bool {
        guard let userID = session.userID else { return false }
        return photo.uploader?.id == userID || (session.user?.canManageFonts ?? false)
    }

    var body: some View {
        List {
            if let error {
                Text(error).foregroundStyle(.red)
            }
            if let photos {
                if photos.isEmpty {
                    Text(L10n.t("gallery.empty")).foregroundStyle(.secondary)
                }
                ForEach(FontPhoto.Kind.allCases, id: \.self) { kind in
                    let group = photos.filter { $0.kind == kind }
                    if !group.isEmpty {
                        Section(L10n.t("gallery.kind.\(kind.rawValue)")) {
                            ForEach(group) { photo in
                                GalleryRow(photo: photo)
                                    .confirmsDestructive(L10n.t("image.confirmRemove"),
                                                         isPresented: Binding(get: { removing?.id == photo.id },
                                                                              set: { if !$0 { removing = nil } }),
                                                         action: L10n.t("image.remove")) { remove(photo) }
                                    .contextMenu {
                                        if canManage(photo) {
                                            Button {
                                                caption = photo.caption ?? ""
                                                captioning = photo
                                            } label: { Label(L10n.t("gallery.caption"), systemImage: "text.cursor") }
                                            Button(role: .destructive) { removing = photo } label: {
                                                Label(L10n.t("image.remove"), systemImage: "trash")
                                            }
                                        }
                                    }
                            }
                        }
                    }
                }
            } else if error == nil {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(L10n.t("gallery.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if session.isSignedIn {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { adding = true } label: { Label(L10n.t("gallery.add"), systemImage: "plus") }
                }
            }
        }
        .task { await load() }
        .alert(L10n.t("gallery.caption"), isPresented: Binding(get: { captioning != nil }, set: { if !$0 { captioning = nil } })) {
            TextField(L10n.t("gallery.caption"), text: $caption)
            Button(L10n.t("form.save")) {
                guard let photo = captioning else { return }
                let text = caption.trimmingCharacters(in: .whitespacesAndNewlines)
                Task {
                    do {
                        _ = try await APIClient.shared.updateFontPhoto(photo.id, of: fontID, caption: text.isEmpty ? nil : text)
                        await load()
                    } catch { self.error = ErrorText.describe(error) }
                }
            }
            Button(L10n.t("form.cancel"), role: .cancel) {}
        }
        .sheet(isPresented: $adding) {
            AddGalleryPhotoSheet(fontID: fontID) { await load() }
        }
    }

    private func remove(_ photo: FontPhoto) {
        Task {
            do {
                try await APIClient.shared.deleteFontPhoto(photo.id, of: fontID)
                await load()
            } catch { self.error = ErrorText.describe(error) }
        }
    }

    private func load() async {
        do {
            photos = try await APIClient.shared.fontPhotos(fontID)
            error = nil
        } catch {
            self.error = ErrorText.describe(error)
        }
    }
}

private struct GalleryRow: View {
    let photo: FontPhoto

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: APIClient.shared.imageURL(photo.url)) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Color(.secondarySystemFill).frame(height: 200).overlay { ProgressView() }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            if let caption = photo.caption, !caption.isEmpty {
                Text(caption)
            }
            let who = photo.uploader?.username.map { "@\($0)" }
            let when = photo.createdAt.map { RelativeTime.string(since: $0) }
            let line = [who, when].compactMap { $0 }
            if !line.isEmpty {
                Text(line.joined(separator: " · ")).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct AddGalleryPhotoSheet: View {
    let fontID: UUID
    let onAdded: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var photo: PhotoPreparer.Prepared?
    /// The camera hands over pixels without EXIF: the date and position are the facts.
    @State private var showsCamera = false
    @State private var readingPhoto = false
    @Environment(LocationService.self) private var location
    @State private var kind: FontPhoto.Kind = .fountain
    @State private var caption = ""
    @State private var isSending = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
                Section {
                    PhotoSlot(jpeg: photo?.jpeg,
                              canTakePhoto: UIImagePickerController.isSourceTypeAvailable(.camera),
                              onTakePhoto: { showsCamera = true },
                              onChosen: { data in
                                  guard let prepared = try? PhotoPreparer.prepare(data) else { return false }
                                  photo = prepared
                                  return true
                              },
                              onRemove: { photo = nil },
                              onReadingChanged: { readingPhoto = $0 })
                } footer: {
                    Text(L10n.t("gallery.addHelp"))
                }
                Section(L10n.t("gallery.kind")) {
                    Picker(L10n.t("gallery.kind"), selection: $kind) {
                        ForEach(FontPhoto.Kind.allCases, id: \.self) { Text(L10n.t("gallery.kind.\($0.rawValue)")).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section {
                    TextField(L10n.t("gallery.caption"), text: $caption, axis: .vertical)
                } footer: {
                    Text(L10n.t("gallery.captionHint"))
                }
            }
            .navigationTitle(L10n.t("gallery.add"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(role: .close) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isSending {
                        ProgressView()
                    } else {
                        Button(L10n.t("form.save"), action: send).disabled(photo == nil || readingPhoto)
                    }
                }
            }
            .fullScreenCover(isPresented: $showsCamera) {
                CameraPicker { jpeg in
                    showsCamera = false
                    guard let jpeg else { return }
                    guard let prepared = try? PhotoPreparer.prepare(jpeg) else {
                        error = L10n.t("ios.photo.unreadable")
                        return
                    }
                    var meta = PhotoMeta(takenAt: .now)
                    if location.isAuthorized, let fix = location.location,
                       fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= RemoteReview.maxAccuracy,
                       abs(fix.timestamp.timeIntervalSinceNow) < 180 {
                        meta.latitude = fix.coordinate.latitude
                        meta.longitude = fix.coordinate.longitude
                    }
                    photo = PhotoPreparer.Prepared(jpeg: prepared.jpeg, meta: meta)
                }
                .ignoresSafeArea()
            }
        }
    }

    private func send() {
        guard let photo else { return }
        isSending = true
        error = nil
        Task {
            defer { isSending = false }
            do {
                let url = try await APIClient.shared.uploadImage(photo.jpeg, meta: photo.meta)
                let text = caption.trimmingCharacters(in: .whitespacesAndNewlines)
                _ = try await APIClient.shared.addFontPhoto(fontID, url: url, kind: kind, caption: text.isEmpty ? nil : text)
                await onAdded()
                dismiss()
            } catch {
                self.error = ErrorText.describe(error)
            }
        }
    }
}
