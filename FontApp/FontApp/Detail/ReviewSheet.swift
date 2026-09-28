import PhotosUI
import SwiftUI

/// The full review, as the web's "new update": status, stars, what you saw and a photo,
/// all optional but not all empty. The three chips stay the quick way; this is for
/// when there is more to say.
struct ReviewSheet: View {
    let fontID: UUID
    let onPosted: () async -> Void

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var draft = Draft()
    @State private var pickerItem: PhotosPickerItem?
    @State private var photo: Data?
    @State private var isSending = false
    @State private var error: String?

    struct Draft: Codable, Equatable {
        var status: String?
        var rating = 0
        var body = ""
        var isEmpty: Bool { status == nil && rating == 0 && body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var draftKey: String { FormDraft.key("review", user: session.userID, font: fontID) }

    var body: some View {
        NavigationStack {
            Form {
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
                Section(L10n.t("update.status").trimmingCharacters(in: CharacterSet(charactersIn: ": "))) {
                    Picker(L10n.t("update.status").trimmingCharacters(in: CharacterSet(charactersIn: ": ")),
                           selection: $draft.status) {
                        Text("—").tag(String?.none)
                        ForEach(WaterStatus.allCases, id: \.self) { status in
                            Text("\(status.emoji) \(L10n.t(status.labelKey))").tag(Optional(status.rawValue))
                        }
                    }
                    .pickerStyle(.menu)
                }
                Section(L10n.t("update.rating").trimmingCharacters(in: CharacterSet(charactersIn: ": "))) {
                    StarPicker(rating: $draft.rating)
                }
                Section {
                    TextField(L10n.t("update.howNowOpt"), text: $draft.body, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label(photo == nil ? L10n.t("ios.choosePhoto") : L10n.t("detail.replacePhoto"),
                              systemImage: "photo.on.rectangle")
                    }
                    if let photo, let image = UIImage(data: photo) {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 180)
                    }
                }
            }
            .navigationTitle(L10n.t("detail.newUpdate"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSending {
                        ProgressView()
                    } else {
                        Button(L10n.t("update.publish"), action: send)
                            .disabled(draft.isEmpty && photo == nil)
                    }
                }
            }
            .onAppear { draft = FormDraft.load(Draft.self, key: draftKey) ?? Draft() }
            // Closing keeps the draft; only sending removes it.
            .onChange(of: draft) { FormDraft.save(draft.isEmpty ? nil : draft, key: draftKey) }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task { photo = try? await item.loadTransferable(type: Data.self) }
            }
        }
    }

    private func send() {
        isSending = true
        error = nil
        Task {
            defer { isSending = false }
            do {
                var review = ComposedReview(waterStatus: draft.status,
                                            rating: draft.rating > 0 ? draft.rating : nil,
                                            body: draft.body.trimmingCharacters(in: .whitespacesAndNewlines))
                if let photo {
                    // The original file, so its EXIF date and place travel as separate fields.
                    let prepared = try await Task.detached(priority: .userInitiated) {
                        try PhotoPreparer.prepare(photo)
                    }.value
                    review.image = try await APIClient.shared.uploadImage(prepared.jpeg, meta: prepared.meta)
                }
                _ = try await APIClient.shared.postComment(on: fontID, review)
                FormDraft.save(Draft?.none, key: draftKey)
                NotificationCenter.default.post(name: .fontChanged, object: fontID)
                await onPosted()
                dismiss()
            } catch {
                self.error = ErrorText.describe(error)
            }
        }
    }
}

/// One to five stars; tapping the current one clears it.
struct StarPicker: View {
    @Binding var rating: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { n in
                Button {
                    rating = rating == n ? 0 : n
                } label: {
                    Image(systemName: n <= rating ? "star.fill" : "star")
                        .font(.title2)
                        .foregroundStyle(n <= rating ? .yellow : .secondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("update.rating"))
        .accessibilityValue("\(rating)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: rating = min(5, rating + 1)
            case .decrement: rating = max(0, rating - 1)
            @unknown default: break
            }
        }
    }
}
