import SwiftUI

/// The full review, as the web's "new update": status, stars, what you saw and a photo,
/// all optional but not all empty. The three chips stay the quick way; this is for
/// when there is more to say.
struct ReviewSheet: View {
    let fontID: UUID
    var fontName: String?
    /// Correcting your own review (or any, as an admin) instead of writing a new one.
    var editing: CommentResponse?
    let onPosted: () async -> Void

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(LocationService.self) private var location
    @State private var draft = Draft()
    @State private var photo: PhotoPreparer.Prepared?
    /// A photo just taken: the camera's JPEG carries no EXIF, so when and where come from
    /// the moment and the position (as the new-fountain form does).
    @State private var showsCamera = false
    @State private var readingPhoto = false
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
                    MentionField(placeholder: L10n.t("update.howNowOpt"), text: $draft.body)
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
                }
            }
            .navigationTitle(L10n.t(editing == nil ? "detail.newUpdate" : "detail.edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
                // As Apple's own forms on iOS 26: an icon in a filled button, which leaves
                // the title its room. The text stays as the accessibility label.
                ToolbarItem(placement: .confirmationAction) {
                    if isSending {
                        ProgressView()
                    } else {
                        Button(L10n.t(editing == nil ? "update.publish" : "form.save"),
                               systemImage: editing == nil ? "arrow.up" : "checkmark", action: send)
                            .buttonStyle(.glassProminent)
                            .tint(session.isStaff ? Color.staff : .accentColor)
                            .disabled((draft.isEmpty && photo == nil) || readingPhoto)
                    }
                }
            }
            .onAppear {
                if let editing {
                    draft = Draft(status: editing.waterStatus, rating: editing.rating ?? 0, body: editing.body)
                } else {
                    draft = FormDraft.load(Draft.self, key: draftKey) ?? Draft()
                }
            }
            // Closing keeps the draft; only sending removes it. A correction has no draft.
            .onChange(of: draft) {
                if editing == nil { FormDraft.save(draft.isEmpty ? nil : draft, key: draftKey) }
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
                    if let prepared = try? PhotoPreparer.prepare(data) {
                        photo = PhotoPreparer.Prepared(jpeg: prepared.jpeg, meta: meta)
                    } else {
                        error = L10n.t("ios.photo.unreadable")
                    }
                }
                .ignoresSafeArea()
            }
        }
    }

    private func send() {
        isSending = true
        error = nil
        Task {
            defer { isSending = false }
            var review = ComposedReview(waterStatus: draft.status,
                                        rating: draft.rating > 0 ? draft.rating : nil,
                                        body: draft.body.trimmingCharacters(in: .whitespacesAndNewlines),
                                        image: editing?.image)
            let prepared = photo
            do {
                if let prepared {
                    review.image = try await APIClient.shared.uploadImage(prepared.jpeg, meta: prepared.meta)
                }
                if let editing {
                    _ = try await APIClient.shared.updateComment(editing.id, on: fontID, review)
                } else {
                    _ = try await APIClient.shared.postComment(on: fontID, review)
                }
                done()
            } catch let failure as APIError where failure.status == 0 && editing == nil {
                // No signal, in front of the fountain: the web queues it, so does the app.
                review.image = nil
                do {
                    try Outbox.shared.enqueueComment(review, jpeg: prepared?.jpeg, meta: prepared?.meta,
                                                     fontID: fontID, fontName: fontName)
                    done()
                } catch {
                    self.error = ErrorText.describe(failure)
                }
            } catch {
                self.error = ErrorText.describe(error)
            }
        }
    }
}

extension ReviewSheet {
    fileprivate func done() {
        FormDraft.save(Draft?.none, key: draftKey)
        NotificationCenter.default.post(name: .fontChanged, object: fontID)
        Task { await onPosted() }
        dismiss()
    }
}

/// One to five stars: tap one, or slide the finger along them (as the App Store's
/// rating); tapping the current one clears it.
struct StarPicker: View {
    @Binding var rating: Int

    private static let size: CGFloat = 44
    private static let spacing: CGFloat = 4
    /// The rating when the finger came down, to tell "tap the current star" apart.
    @State private var startRating: Int?

    var body: some View {
        HStack(spacing: Self.spacing) {
            ForEach(1...5, id: \.self) { n in
                Image(systemName: n <= rating ? "star.fill" : "star")
                    .font(.title2)
                    .foregroundStyle(n <= rating ? .yellow : .secondary)
                    .frame(width: Self.size, height: Self.size)
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if startRating == nil { startRating = rating }
                    let moved = abs(value.translation.width) > 8
                    let star = Self.star(at: value.location.x)
                    // A tap on the current star waits for the finger to lift (it clears);
                    // anything else follows the finger at once.
                    if moved || star != startRating { set(star) }
                }
                .onEnded { value in
                    let star = Self.star(at: value.location.x)
                    if abs(value.translation.width) <= 8, star == startRating { set(0) }
                    startRating = nil
                }
        )
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

    /// The star under the finger; past the left edge, none.
    private static func star(at x: CGFloat) -> Int {
        if x < 0 { return 0 }
        return min(5, Int(x / (size + spacing)) + 1)
    }

    private func set(_ value: Int) {
        guard value != rating else { return }
        rating = value
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
