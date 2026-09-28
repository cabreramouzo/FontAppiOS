import PhotosUI
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
                            ForEach(group) { GalleryRow(photo: $0) }
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
        .sheet(isPresented: $adding) {
            AddGalleryPhotoSheet(fontID: fontID) { await load() }
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
    @State private var pickerItem: PhotosPickerItem?
    @State private var photo: Data?
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
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label(L10n.t("gallery.choose"), systemImage: "photo.on.rectangle")
                    }
                    if let photo, let image = UIImage(data: photo) {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 200)
                    }
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
                        Button(L10n.t("form.save"), action: send).disabled(photo == nil)
                    }
                }
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task { photo = try? await item.loadTransferable(type: Data.self) }
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
                let prepared = try await Task.detached(priority: .userInitiated) {
                    try PhotoPreparer.prepare(photo)
                }.value
                let url = try await APIClient.shared.uploadImage(prepared.jpeg, meta: prepared.meta)
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
