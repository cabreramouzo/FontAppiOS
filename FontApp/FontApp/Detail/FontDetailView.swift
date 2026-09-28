import MapKit
import SwiftUI

/// A fountain's page: status with its confidence, the quick review, directions, photo,
/// facts, reviews and reports.
struct FontDetailView: View {
    @Environment(SessionStore.self) private var session
    @Environment(Favorites.self) private var favorites
    @State private var favoriteError: String?
    @State private var model: FontDetailModel
    @State private var showsSignIn = false
    @State private var showsCamera = false
    @State private var editor: FontEditModel?
    @Environment(LocationService.self) private var location
    /// What the caller already knows, shown while the rest loads.
    private let preview: FontSummary?

    init(fontID: UUID, preview: FontSummary? = nil) {
        _model = State(initialValue: FontDetailModel(fontID: fontID, summary: preview))
        self.preview = preview
    }

    var body: some View {
        Group {
            switch model.state {
            case .loading:
                ProgressView(L10n.t("detail.loading"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ContentUnavailableView {
                    Label(message, systemImage: "wifi.exclamationmark")
                } actions: {
                    Button(L10n.t("activity.retry")) { Task { await model.load() } }
                        .buttonStyle(.bordered)
                }
            case .loaded(let font):
                content(font, offlineNote: nil)
            case .offline(let font, let message):
                content(font, offlineNote: message)
            }
        }
        .navigationTitle(L10n.fontName(loadedFont?.name ?? preview?.name))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let font = loadedFont { star(font) }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if case .loaded(let font) = model.state, let userID = session.userID {
                    Button {
                        editor = FontEditModel(font: font, userID: userID)
                    } label: {
                        Label(L10n.t("detail.edit"), systemImage: "pencil")
                    }
                    .tint(session.isStaff ? Color.staff : .accentColor)
                    .accessibilityHint(L10n.t("detail.editInfoHint"))
                    .accessibilityIdentifier("fontDetail.edit")
                }
            }
        }
        .task { await model.load() }
        .alert(favoriteError ?? "", isPresented: Binding(get: { favoriteError != nil }, set: { if !$0 { favoriteError = nil } })) {
            Button("OK", role: .cancel) {}
        }
        .sheet(isPresented: $showsSignIn) { SignInView() }
        .sheet(item: $editor) { editor in
            FontEditSheet(model: editor) { font in
                model.didEdit(font)
                Task { await model.load() }
            }
        }
        .fullScreenCover(isPresented: $showsCamera) {
            CameraPicker { jpeg in
                showsCamera = false
                guard let jpeg, let upload = model.photoUpload else { return }
                let fix = location.isAuthorized ? location.location : nil
                Task { if await upload.upload(cameraJPEG: jpeg, fix: fix) { await model.load() } }
            }
            .ignoresSafeArea()
        }
        .remoteReviewAlert(model.quickReview) { await model.load() }
    }

    /// The star: one tap adds it to the Favourites tab. Signed out, it asks to sign in.
    private func star(_ font: FontDetail) -> some View {
        let on = favorites.contains(font.id)
        return Button {
            guard session.isSignedIn else { showsSignIn = true; return }
            Task {
                do { try await favorites.toggle(font.summary) } catch { favoriteError = ErrorText.describe(error) }
            }
        } label: {
            Label(L10n.t(on ? "favorite.saved" : "favorite.save"), systemImage: on ? "star.fill" : "star")
        }
        .tint(on ? .yellow : nil)
        .sensoryFeedback(.selection, trigger: on)
        .accessibilityIdentifier("fontDetail.favorite")
    }

    private var loadedFont: FontDetail? { model.font }

    private func content(_ font: FontDetail, offlineNote: String?) -> some View {
        List {
            if let offlineNote {
                // Only what the map knew: reviews and reports need signal. Reviewing and
                // adding a photo still work — they go to the outbox.
                Section {
                    Label(offlineNote, systemImage: "wifi.slash")
                    if OfflineZones.shared.font(font.id) != nil {
                        // Without this, a page with no reviews looks like a fountain nobody
                        // ever checked, which is the opposite of what is known.
                        Text(L10n.t("offline.fromZone")).font(.footnote).foregroundStyle(.secondary)
                    }
                    Button(L10n.t("activity.retry")) { Task { await model.load() } }
                        .frame(minHeight: 44)
                }
            }
            // What decides whether to walk there comes first; at half height the sheet
            // shows the status and the way there, and the photo is one swipe away.
            statusSection(font)
            if let quick = model.quickReview {
                QuickReviewSection(model: quick, onChange: { await model.load() },
                                   onSignIn: { showsSignIn = true })
            }
            Section { directionsButton(font) }
            if font.image == nil, let upload = model.photoUpload {
                PhotoSection(model: upload, onUploaded: { await model.load() },
                             onCamera: { showsCamera = true })
            } else {
                Section {
                    // A photo saved with an offline zone is read from the phone.
                    PhotoView(url: OfflineZones.shared.photoFile(for: font.image)
                                ?? APIClient.shared.imageURL(font.image))
                        .listRowInsets(EdgeInsets())
                }
            }
            factsSection(font)
            if !model.reviews.isEmpty {
                let confirmable = session.isSignedIn ? model.confirmable(by: session.user?.id) : nil
                Section(L10n.t("detail.statusReviews")) {
                    ForEach(model.reviews) { review in
                        ReviewRow(review: review)
                        if review.id == confirmable?.id {
                            stillTheSameButton(review)
                        }
                    }
                    if let error = model.actionError {
                        Text(error).font(.subheadline).foregroundStyle(.red)
                    }
                }
            }
            Section(L10n.t("detail.incidents", ["n": model.reports.count])) {
                if model.reports.isEmpty {
                    Text(L10n.t("detail.noIncidents")).foregroundStyle(.secondary)
                }
                ForEach(model.reports) { ReportRow(report: $0) }
            }
        }
        .listStyle(.insetGrouped)
    }

    /// "Still the same": backs someone else's latest report instead of repeating it.
    private func stillTheSameButton(_ review: CommentResponse) -> some View {
        let active = review.confirmedByMe ?? false
        return Button {
            Task { await model.setStillTheSame(review, !active) }
        } label: {
            Label(L10n.t("confirm.keepSame"), systemImage: active ? "hand.thumbsup.fill" : "hand.thumbsup")
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .tint(session.isStaff ? Color.staff : .accentColor)
        .accessibilityHint(L10n.t(active ? "confirm.titleActive" : "confirm.titleInactive"))
    }

    private func directionsButton(_ font: FontDetail) -> some View {
        Button {
            let item = MKMapItem(location: CLLocation(latitude: font.latitude, longitude: font.longitude),
                                 address: nil)
            item.name = L10n.fontName(font.name)
            item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
        } label: {
            WideButtonLabel(L10n.t("detail.directions"), systemImage: "figure.walk")
        }
        .buttonStyle(.borderedProminent)
        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
    }

    private func statusSection(_ font: FontDetail) -> some View {
        let evidence = model.evidence(for: font)
        let level = Confidence.level(of: evidence)
        let status = WaterStatus(evidence.lastWaterStatus)
        // A stale status is still shown, but not as the current one.
        let title = level == .stale ? "detail.lastReportedStatus" : "detail.currentStatus"
        return Section(L10n.t(title)) {
            if let status {
                HStack {
                    StatusBadge(status: status)
                    Spacer()
                    if let date = evidence.lastUpdate {
                        Text(RelativeTime.string(since: date))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("\(level.emoji) \(L10n.t(level.labelKey))").font(.headline)
                Text(L10n.t(level.detailKey)).font(.subheadline).foregroundStyle(.secondary)
                if evidence.latestConfirmations > 0 {
                    Text(evidence.latestConfirmations == 1
                         ? L10n.t("detail.confirmedByOne")
                         : L10n.t("detail.confirmedByMany", ["n": evidence.latestConfirmations]))
                        .font(.subheadline)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func factsSection(_ font: FontDetail) -> some View {
        Section {
            LabeledContent(label("detail.type"),
                           value: font.source.map { L10n.t("source.\($0.rawValue)") } ?? L10n.t("detail.unknownType"))
            LabeledContent(label("detail.drinkability"),
                           value: font.drinkable.map { L10n.t("drink.\($0.rawValue)") } ?? L10n.t("detail.unknownDrink"))
            if let municipality = font.municipality {
                LabeledContent(label("detail.municipality"), value: municipality)
            }
            if let region = font.region {
                LabeledContent(label("detail.region"), value: region)
            }
            if let country = font.country {
                LabeledContent(label("detail.country"), value: country)
            }
            if let description = font.description, !description.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(label("detail.description")).font(.subheadline).foregroundStyle(.secondary)
                    Text(description)
                }
            }
        }
    }

    /// The web labels end in a colon ("Tipus:"); a `LabeledContent` row does not need it.
    private func label(_ key: String) -> String {
        L10n.t(key).trimmingCharacters(in: CharacterSet(charactersIn: ": "))
    }
}

/// Icon and title centred together in a full-width button. A `Label` inside a list row
/// takes the list's label style: the icon goes missing and the title keeps its column,
/// so it sits off centre.
struct WideButtonLabel: View {
    let title: String
    let systemImage: String

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
    }
}

struct StatusBadge: View {
    let status: WaterStatus

    var body: some View {
        Text("\(status.emoji) \(L10n.t(status.labelKey))")
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(status.color.opacity(0.18), in: Capsule())
            .overlay(Capsule().strokeBorder(status.color, lineWidth: 1))
    }
}

private struct PhotoView: View {
    let url: URL?

    var body: some View {
        if let url {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    // Without signal and not saved, or a format iOS cannot draw: say so
                    // instead of spinning for ever.
                    Color(.secondarySystemFill).overlay {
                        Label(L10n.t("photo.failed"), systemImage: "photo.badge.exclamationmark")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                default:
                    Color(.secondarySystemFill).overlay { ProgressView() }
                }
            }
            .frame(height: 240)
            .frame(maxWidth: .infinity)
            .clipped()
            .accessibilityHidden(true)
        } else {
            Label(L10n.t("detail.noPhotoYet"), systemImage: "photo")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 80)
        }
    }
}

private struct ReviewRow: View {
    let review: CommentResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let status = WaterStatus(review.waterStatus) { StatusBadge(status: status) }
                Spacer()
                Text(RelativeTime.string(since: review.createdAt))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if !review.body.isEmpty { Text(review.body) }
            if let url = APIClient.shared.imageURL(review.image) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color(.secondarySystemFill)
                }
                .frame(width: 120, height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            HStack(spacing: 8) {
                Text(review.username ?? L10n.t("review.anon"))
                if let n = review.confirmations, n > 0 {
                    Text(n == 1 ? L10n.t("detail.confirmedByOne") : L10n.t("detail.confirmedByMany", ["n": n]))
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct ReportRow: View {
    let report: ReportResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if report.isIncident == true, let kind = report.incidentKind,
                   let label = L10n.lookup("incident.\(kind)") {
                    Text(label)
                        .font(.subheadline.weight(.semibold))
                }
                if report.resolvedAt != nil {
                    Label(L10n.t("report.resolved"), systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.green)
                }
                Spacer()
                Text(RelativeTime.string(since: report.createdAt))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Text(report.message)
            Text(report.username ?? L10n.t("review.anon"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.leading, report.parentID == nil ? 0 : 16)
        .padding(.vertical, 4)
    }
}
