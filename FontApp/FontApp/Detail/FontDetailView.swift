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
    @State private var nearWater: NearestWater?
    @State private var flagging = false
    @State private var notice: String?
    @State private var copied = false
    @Environment(\.showOnMap) private var showOnMap
    @Environment(\.dismiss) private var dismiss
    @State private var writesReview = false
    @State private var reportTarget: ReportTarget?
    @State private var suggestsDuplicate = false
    @State private var confirmsDelete = false
    @State private var creatorName: String?
    @State private var creatorTier: String?
    @State private var photoAuthor: String?
    /// Someone whose @name was tapped: their profile goes on this page's stack.
    @State private var profile: String?
    @State private var capabilities: Set<String> = []
    @State private var editingReview: CommentResponse?
    @State private var editingReport: ReportResponse?
    @State private var deleting: Deletion?
    @State private var photoRemoval: PhotoRemovalStatus?
    @State private var coverAction: CoverAction?

    /// Taking the cover down, or asking for it: both confirmed first.
    private enum CoverAction { case remove, request }

    /// A review or a note waiting for "delete?" to be confirmed.
    private enum Deletion { case review(CommentResponse), report(ReportResponse) }

    /// A new comment, or a reply to one.
    private struct ReportTarget: Identifiable {
        let replyTo: ReportResponse?
        var id: UUID { replyTo?.id ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")! }
    }
    @Environment(LocationService.self) private var location
    @State private var approach = ApproachTracker()
    /// What the caller already knows, shown while the rest loads.
    private let preview: FontSummary?

    /// Over the map: the close button sits in the header, beside the title, and there is
    /// no navigation bar above it. Pushed in a list, the system back button stays.
    private let onClose: (() -> Void)?

    init(fontID: UUID, preview: FontSummary? = nil, onClose: (() -> Void)? = nil) {
        _model = State(initialValue: FontDetailModel(fontID: fontID, summary: preview))
        self.preview = preview
        self.onClose = onClose
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
        // The name is the header's, in full: a one-line bar title cut it ("Font de la quint…").
        .navigationTitle(L10n.fontName(loadedFont?.name ?? preview?.name))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) } }
        .toolbarVisibility(onClose == nil ? .automatic : .hidden, for: .navigationBar)
        .task { await model.load() }
        .navigationDestination(item: $profile) { UserProfileScreen(handle: $0) }
        .environment(\.openProfile) { profile = $0 }
        .onAppear { approach.start() }
        .onDisappear { approach.stop() }
        // Dry, broken or gone: where the nearest water is, as the web says it. Only then:
        // a fountain that flows needs no alternative.
        .task(id: loadedFont.map { model.evidence(for: $0).lastWaterStatus }) {
            guard let font = loadedFont,
                  ["dry", "broken", "gone"].contains(model.evidence(for: font).lastWaterStatus ?? "") else {
                nearWater = nil
                return
            }
            nearWater = try? await APIClient.shared.nearestWater(font.id)
        }
        .task(id: loadedFont?.creator?.id) {
            creatorName = nil; creatorTier = nil
            guard let creator = loadedFont?.creator?.id else { return }
            creatorName = try? await APIClient.shared.username(of: creator)
            creatorTier = (try? await APIClient.shared.badges(of: creator))?.first { $0.family == "discoverer" }?.tier
        }
        .task(id: loadedFont.map { "\($0.id)\($0.image ?? "")" }) {
            photoAuthor = nil
            guard let font = loadedFont, font.image != nil else { return }
            photoAuthor = try? await APIClient.shared.photoAuthor(font.id)
        }
        .task(id: session.userID) { capabilities = await Capabilities.of(session.userID) }
        .task(id: "\(session.userID?.uuidString ?? "")\(loadedFont?.image ?? "")") {
            photoRemoval = nil
            guard session.isSignedIn, let font = loadedFont, font.image != nil else { return }
            photoRemoval = try? await APIClient.shared.photoRemovalStatus(font.id)
        }
        .confirmationDialog(L10n.t(coverAction == .remove ? "image.confirmRemove" : "image.confirmRequestRemoval"),
                            isPresented: Binding(get: { coverAction != nil }, set: { if !$0 { coverAction = nil } }),
                            titleVisibility: .visible) {
            Button(L10n.t(coverAction == .remove ? "image.remove" : "image.requestRemoval"), role: .destructive) {
                if let action = coverAction { cover(action) }
            }
            Button(L10n.t("form.cancel"), role: .cancel) {}
        }
        .sheet(isPresented: $writesReview) {
            if let font = loadedFont {
                ReviewSheet(fontID: font.id, fontName: font.name) { await model.load() }
            }
        }
        .sheet(item: $editingReview) { review in
            if let font = loadedFont {
                ReviewSheet(fontID: font.id, fontName: font.name, editing: review) { await model.load() }
            }
        }
        .sheet(item: $editingReport) { report in
            if let font = loadedFont {
                ReportSheet(fontID: font.id, editing: report) { await model.load() }
            }
        }
        .confirmationDialog(deleting.map { if case .review = $0 { L10n.t("review.confirmDelete") } else { L10n.t("detail.confirmDeleteIncident") } } ?? "",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button(L10n.t("detail.delete"), role: .destructive) { if let deleting { delete(deleting) } }
            Button(L10n.t("form.cancel"), role: .cancel) {}
        }
        .sheet(item: $reportTarget) { target in
            if let font = loadedFont {
                ReportSheet(fontID: font.id, replyTo: target.replyTo) { await model.load() }
            }
        }
        .sheet(isPresented: $suggestsDuplicate) {
            if let font = loadedFont {
                DuplicateSheet(font: font) { notice = $0 }
            }
        }
        .confirmationDialog(L10n.t("detail.confirmDeleteFont"), isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button(L10n.t("detail.delete"), role: .destructive, action: deleteFont)
            Button(L10n.t("form.cancel"), role: .cancel) {}
        }
        .confirmationDialog(L10n.t("flag.fontTitle"), isPresented: $flagging, titleVisibility: .visible) {
            ForEach(["fake", "duplicate", "nonexistent", "spam", "abuse"], id: \.self) { reason in
                Button(L10n.t("flag.reason.\(reason)"), role: .destructive) { flag(reason) }
            }
            Button(L10n.t("form.cancel"), role: .cancel) {}
        } message: {
            Text(L10n.t("flag.fontHelp"))
        }
        .alert(notice ?? "", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("OK", role: .cancel) {}
        }
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

    private var loadedFont: FontDetail? { model.font }

    /// The place card's head, as Apple Maps opens a place: the name in full, where it is
    /// and what kind, its state in one line, and a row of equal actions under the thumb.
    /// Only one close button, and nothing else beside it.
    private func header(_ font: FontDetail) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.fontName(font.name))
                            .font(.title2.bold())
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        let place = [font.source?.emojiLabel,
                                     font.municipality ?? font.region].compactMap { $0 }
                        if !place.isEmpty {
                            Text(place.joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    if let onClose {
                        Button(action: onClose) {
                            Image(systemName: "xmark").font(.body.weight(.semibold)).frame(width: 30, height: 30)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .accessibilityLabel(L10n.t("ios.close"))
                    }
                }
                statusRow(font)
                actions(font)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
        }
    }

    /// As Apple Maps' place card: the main action wide and with its words, the others
    /// round icons of the same size. Four labelled buttons cut every label short.
    private func actions(_ font: FontDetail) -> some View {
        let starred = favorites.contains(font.id)
        let tint = session.isStaff ? Color.staff : Color.accentColor
        return GlassEffectContainer {
            HStack(spacing: 10) {
                // Next to the fountain (most visits), the way there is noise and the page's
                // weight belongs to the three chips; it only grows, with the distance,
                // when the fountain is clearly elsewhere.
                if let far = farDistance(font) {
                    Button { openDirections(font) } label: {
                        // The distance is what says it is worth it; "Directions" cut it short
                        // in most languages, and VoiceOver still hears both.
                        Label(far, systemImage: "figure.walk")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.tint(tint).interactive(), in: Capsule())
                    .accessibilityLabel("\(L10n.t("detail.directions")), \(far)")
                } else {
                    Button { openDirections(font) } label: { CircleIcon(systemImage: "figure.walk") }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: Circle())
                        .accessibilityLabel(L10n.t("detail.directions"))
                }
                // Away from the map it goes there; over the map it zooms onto the fountain.
                if let showOnMap {
                    Button { showOnMap(FontSummary(font)) } label: { CircleIcon(systemImage: "map") }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: Circle())
                        .accessibilityLabel(L10n.t("detail.viewOnMap"))
                }
                Button { toggleStar(font) } label: {
                    CircleIcon(systemImage: starred ? "star.fill" : "star", color: starred ? .yellow : .primary)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: Circle())
                .sensoryFeedback(.selection, trigger: starred)
                .accessibilityLabel(L10n.t(starred ? "favorite.saved" : "favorite.save"))
                .accessibilityIdentifier("fontDetail.favorite")
                ShareLink(item: shareText(font)) { CircleIcon(systemImage: "square.and.arrow.up") }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: Circle())
                    .accessibilityLabel(L10n.t("detail.share"))
                moreMenu(font)
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: Circle())
            }
        }
    }

    private func openDirections(_ font: FontDetail) {
        let item = MKMapItem(location: CLLocation(latitude: font.latitude, longitude: font.longitude), address: nil)
        item.name = L10n.fontName(font.name)
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }

    /// The distance, written, when the fountain is clearly elsewhere (beyond where a
    /// new fountain counts as "here"); nil next to it or without a position.
    private func farDistance(_ font: FontDetail) -> String? {
        guard location.isAuthorized, let me = location.location else { return nil }
        let d = me.distance(from: CLLocation(latitude: font.latitude, longitude: font.longitude))
        guard d > NewFontPlacement.nearbyMeters else { return nil }
        return d < 1000 ? "\(Int(d.rounded(.toNearestOrEven) / 10) * 10) m"
            : Measurement(value: d / 1000, unit: UnitLength.kilometers)
                .formatted(.measurement(width: .abbreviated, numberFormatStyle: .number.precision(.fractionLength(1))))
    }

    private func toggleStar(_ font: FontDetail) {
        guard session.isSignedIn else { showsSignIn = true; return }
        Task {
            do { try await favorites.toggle(font.summary) } catch { favoriteError = ErrorText.describe(error) }
        }
    }

    /// Share, copy the coordinates and report: what the web has as a row of buttons, here
    /// in the "more" menu, where iOS keeps the actions nobody needs on every visit.
    private func moreMenu(_ font: FontDetail) -> some View {
        Menu {
            if case .loaded = model.state, let userID = session.userID {
                Button {
                    editor = FontEditModel(font: font, userID: userID)
                } label: {
                    Label(L10n.t("detail.edit"), systemImage: "pencil")
                }
                .accessibilityHint(L10n.t("detail.editInfoHint"))
                .accessibilityIdentifier("fontDetail.edit")
            }
            Button {
                UIPasteboard.general.string = String(format: "%.6f, %.6f", font.latitude, font.longitude)
                copied.toggle()
                notice = L10n.t("toast.coordsCopied")
            } label: {
                Label(String(format: "%.6f, %.6f", font.latitude, font.longitude), systemImage: "doc.on.doc")
            }
            // Whose level already lets them mark it has the real button on the web; two
            // similar buttons doing different things is worse than one.
            if session.isSignedIn, !capabilities.contains("markDuplicate") {
                Button { suggestsDuplicate = true } label: {
                    Label(L10n.t("dup.suggest"), systemImage: "square.on.square")
                }
            }
            // Not on your own fountain, and only with a session, as on the web.
            if let userID = session.userID, font.creator?.id != userID {
                Divider()
                Button(role: .destructive) { flagging = true } label: {
                    Label(L10n.t("flag.font"), systemImage: "flag")
                }
            }
            // Deleting is for its creator or an admin.
            if let userID = session.userID, font.creator?.id == userID || (session.user?.canManageFonts ?? false) {
                Divider()
                Button(role: .destructive) { confirmsDelete = true } label: {
                    Label(L10n.t("detail.delete"), systemImage: "trash")
                }
            }
        } label: {
            CircleIcon(systemImage: "ellipsis")
        }
        .accessibilityLabel(L10n.t("ios.more"))
        .sensoryFeedback(.success, trigger: copied)
        .accessibilityIdentifier("fontDetail.more")
    }

    /// Says what it is without anyone opening it: it lands in a chat among other things.
    private func shareText(_ font: FontDetail) -> String {
        let lang = Bundle.main.preferredLocalizations.first?.split(separator: "-").first.map(String.init) ?? "ca"
        let link = "https://fontapp.net/fonts/\(font.id.uuidString.lowercased())?lang=\(lang)"
        return L10n.t("detail.shareText", ["name": L10n.fontName(font.name)]) + " " + link
    }

    private func deleteFont() {
        guard let font = loadedFont else { return }
        Task {
            do {
                try await APIClient.shared.deleteFont(font.id)
                NotificationCenter.default.post(name: .fontChanged, object: font.id)
                dismiss()
            } catch {
                notice = ErrorText.describe(error)
            }
        }
    }

    /// Who put it on the map, who reviewed it first and who looks after it now.
    @ViewBuilder private func peopleSection(_ font: FontDetail) -> some View {
        // By date, not by the server's order: the day it pages or caches, order breaks.
        let pioneer = model.reviews.min { $0.createdAt < $1.createdAt }?.username
        let showsPioneer = pioneer != nil && pioneer != creatorName
        if creatorName != nil || showsPioneer || font.mayor != nil {
            Section {
                if let creatorName {
                    LabeledContent(L10n.t("detail.createdBy")) { UserLink(username: creatorName) }
                }
                if showsPioneer, let pioneer {
                    LabeledContent(L10n.t("detail.pioneerBy")) { UserLink(username: pioneer) }
                }
                if let mayor = font.mayor {
                    LabeledContent {
                        VStack(alignment: .trailing, spacing: 2) {
                            UserLink(username: mayor.username)
                            Text(L10n.t("detail.mayorReviews", ["n": mayor.reviews])).font(.caption)
                        }
                    } label: {
                        Text(L10n.t("detail.mayorBy"))
                    }
                    .accessibilityHint(L10n.t("detail.mayorHelp"))
                }
            }
        }
    }

    private func canResolve(_ report: ReportResponse) -> Bool {
        guard let userID = session.userID else { return false }
        return report.userID == userID || (session.user?.canManageFonts ?? false)
            || capabilities.contains("resolveIncident")
    }

    private var isAdmin: Bool { session.user?.canManageFonts ?? false }

    /// Undo the cover you just put; take it down if the fountain is yours or you are an
    /// admin; otherwise ask the moderators to, or withdraw the request.
    @ViewBuilder private func coverControls(_ font: FontDetail) -> some View {
        let manages = isAdmin || (session.userID != nil && font.creator?.id == session.userID)
        if photoRemoval?.canUndo == true {
            HStack {
                Text(L10n.t("image.photoAddedUndo")).font(.subheadline)
                Spacer()
                Button(L10n.t("form.undo")) { undoCover(font) }.buttonStyle(.borderless)
            }
            .frame(minHeight: 44)
        }
        if manages {
            Button(role: .destructive) { coverAction = .remove } label: {
                Label(L10n.t("image.remove"), systemImage: "photo.badge.minus")
            }
            .frame(minHeight: 44)
        } else if let status = photoRemoval, status.canRequest {
            if status.pending {
                HStack {
                    Text(L10n.t("image.removalPending")).font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Button(L10n.t("form.cancel")) { withdrawRemoval(font) }.buttonStyle(.borderless)
                }
                .frame(minHeight: 44)
            } else {
                Button(role: .destructive) { coverAction = .request } label: {
                    Label(L10n.t("image.requestRemoval"), systemImage: "photo.badge.minus")
                }
                .frame(minHeight: 44)
            }
        }
    }

    private func cover(_ action: CoverAction) {
        guard let font = loadedFont else { return }
        Task {
            do {
                switch action {
                case .remove:
                    try await APIClient.shared.removeCover(of: font)
                    NotificationCenter.default.post(name: .fontChanged, object: font.id)
                    await model.load()
                case .request:
                    try await APIClient.shared.requestPhotoRemoval(font.id, true)
                    photoRemoval = try? await APIClient.shared.photoRemovalStatus(font.id)
                    notice = L10n.t("image.removalRequested")
                }
            } catch {
                notice = ErrorText.describe(error)
            }
        }
    }

    private func withdrawRemoval(_ font: FontDetail) {
        Task {
            do {
                try await APIClient.shared.requestPhotoRemoval(font.id, false)
                photoRemoval = try? await APIClient.shared.photoRemovalStatus(font.id)
            } catch { notice = ErrorText.describe(error) }
        }
    }

    private func undoCover(_ font: FontDetail) {
        Task {
            do {
                try await APIClient.shared.undoFontPhoto(font.id)
                notice = L10n.t("image.photoUndone")
                NotificationCenter.default.post(name: .fontChanged, object: font.id)
                await model.load()
            } catch { notice = ErrorText.describe(error) }
        }
    }

    /// Your own note, within the hour: the server says when it is over.
    private func canEdit(_ report: ReportResponse) -> Bool {
        guard let userID = session.userID, report.userID == userID else { return false }
        let elapsed = Date.now.timeIntervalSince(report.createdAt)
        return elapsed >= 0 && elapsed <= 3600
    }

    private func like(_ report: ReportResponse) {
        guard let font = loadedFont else { return }
        Task {
            do {
                _ = try await APIClient.shared.likeReport(report.id, on: font.id, !(report.likedByMe ?? false))
                await model.load()
            } catch {
                notice = ErrorText.describe(error)
            }
        }
    }

    private func delete(_ deletion: Deletion) {
        guard let font = loadedFont else { return }
        Task {
            do {
                switch deletion {
                case .review(let review): try await APIClient.shared.deleteComment(review.id, on: font.id)
                case .report(let report): try await APIClient.shared.deleteReport(report.id, on: font.id)
                }
                NotificationCenter.default.post(name: .fontChanged, object: font.id)
                await model.load()
            } catch {
                notice = ErrorText.describe(error)
            }
        }
    }

    private func reviewAction(_ font: FontDetail, _ action: @escaping () async throws -> Void, done: String? = nil) {
        Task {
            do {
                try await action()
                if let done { notice = done }
                await model.load()
            } catch {
                notice = ErrorText.describe(error)
            }
        }
    }

    /// What can be done with a review: correct or delete yours, report someone else's,
    /// and make its photo the fountain's cover (its creator, an admin, or anyone while
    /// the fountain has none).
    @ViewBuilder private func reviewMenu(_ review: CommentResponse, _ font: FontDetail) -> some View {
        let mine = review.userID != nil && review.userID == session.userID
        if mine || isAdmin {
            Button { editingReview = review } label: { Label(L10n.t("detail.edit"), systemImage: "pencil") }
        }
        if review.image != nil, review.image != font.image,
           session.isSignedIn, font.image == nil || isAdmin || font.creator?.id == session.userID {
            Button {
                reviewAction(font, { try await APIClient.shared.setCoverFromComment(review.id, on: font.id) },
                             done: L10n.t("detail.photoSetAsMain"))
            } label: {
                Label(L10n.t("detail.useAsMainPhoto"), systemImage: "photo")
            }
        }
        if session.isSignedIn, !mine {
            Button(role: .destructive) {
                reviewAction(font, { try await APIClient.shared.flagComment(review.id, on: font.id) },
                             done: L10n.t("flag.done"))
            } label: {
                Label(L10n.t("flag.report"), systemImage: "flag")
            }
        }
        if mine || isAdmin {
            Button(role: .destructive) { deleting = .review(review) } label: {
                Label(L10n.t("detail.delete"), systemImage: "trash")
            }
        }
    }

    private func resolve(_ report: ReportResponse) {
        guard let font = loadedFont else { return }
        Task {
            do {
                _ = try await APIClient.shared.resolveReport(report.id, of: font.id, report.resolvedAt == nil)
                await model.load()
            } catch {
                notice = ErrorText.describe(error)
            }
        }
    }

    private func flag(_ reason: String) {
        guard let font = loadedFont else { return }
        Task {
            do {
                try await APIClient.shared.flagFont(font.id, reason: reason)
                notice = L10n.t("flag.done")
            } catch {
                notice = ErrorText.describe(error)
            }
        }
    }

    private func nearWaterSection(_ water: NearestWater) -> some View {
        let distance = water.distanceKm < 1
            ? "\(Int((water.distanceKm * 1000).rounded())) m"
            : Measurement(value: water.distanceKm, unit: UnitLength.kilometers)
                .formatted(.measurement(width: .abbreviated, numberFormatStyle: .number.precision(.fractionLength(0...1))))
        return Section {
            NavigationLink {
                FontDetailView(fontID: water.id)
            } label: {
                HStack(spacing: 12) {
                    Text("💧").font(.title2).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t("detail.nearWaterTitle", ["dist": distance])).font(.subheadline.bold())
                        Text(L10n.fontName(water.name)).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .frame(minHeight: 44)
            }
        }
    }

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
            // The short card, what the sheet opens at (as the web's popup): the status in
            // one line, the three chips where the thumb is, and the way there. The rest is
            // one swipe up.
            header(font)
            // First, when it shows at all: then you are there, and nothing on the page
            // matters more. The rest of the time it takes no room.
            FinalApproachSection(coordinate: CLLocationCoordinate2D(latitude: font.latitude, longitude: font.longitude),
                                 hasPhoto: font.image != nil, tracker: approach)
            HiddenNotice(font: font)
            if let quick = model.quickReview {
                QuickReviewSection(model: quick, onChange: { await model.load() },
                                   onSignIn: { showsSignIn = true })
            }
            if let nearWater { nearWaterSection(nearWater) }
            statusSection(font)
            let photos = FountainPhoto.all(cover: font.image, reviews: model.reviews)
            if !photos.isEmpty {
                Section {
                    // A photo saved with an offline zone is read from the phone.
                    PhotoCarousel(
                        name: L10n.fontName(font.name), photos: photos,
                        url: { OfflineZones.shared.photoFile(for: $0) ?? APIClient.shared.imageURL($0) },
                        latestID: FountainPhoto.latestReviewPhoto(model.reviews),
                        // As the review's menu: anyone while it has no cover; then its
                        // creator or an admin.
                        canPromote: { review in
                            review.image != font.image && session.isSignedIn
                                && (font.image == nil || isAdmin || font.creator?.id == session.userID)
                        },
                        onPromote: { review in
                            reviewAction(font, { try await APIClient.shared.setCoverFromComment(review.id, on: font.id) },
                                         done: L10n.t("detail.photoSetAsMain"))
                        },
                        exifFor: isAdmin
                            ? CLLocationCoordinate2D(latitude: font.latitude, longitude: font.longitude) : nil)
                    .listRowInsets(EdgeInsets())
                    if font.image != nil { coverControls(font) }
                }
            }
            if font.image == nil, let upload = model.photoUpload {
                PhotoSection(model: upload, onUploaded: { await model.load() },
                             onCamera: { showsCamera = true })
            } else if photos.isEmpty {
                Section { PhotoView(url: nil) }
            }
            Section {
                NavigationLink {
                    GalleryScreen(fontID: font.id)
                } label: {
                    Label(L10n.t("gallery.open"), systemImage: "photo.stack")
                }
            }
            factsSection(font)
            peopleSection(font)
            FontBadgesSection(
                creatorName: creatorName, creatorTier: creatorTier,
                pioneerCounts: font.creator?.id == nil,
                pioneerName: model.reviews.min { $0.createdAt < $1.createdAt }?.username,
                hasPhoto: font.image != nil, photoAuthor: photoAuthor,
                daysSinceCheck: model.evidence(for: font).lastUpdate.map {
                    Int(Date.now.timeIntervalSince($0) / 86_400)
                })
            do {
                let confirmable = session.isSignedIn ? model.confirmable(by: session.user?.id) : nil
                Section(L10n.t("detail.statusReviews")) {
                    Button {
                        if session.isSignedIn { writesReview = true } else { showsSignIn = true }
                    } label: {
                        Label(L10n.t("detail.newUpdate"), systemImage: "square.and.pencil")
                    }
                    .frame(minHeight: 44)
                    ForEach(model.reviews) { review in
                        ReviewRow(review: review)
                            .contextMenu { reviewMenu(review, font) }
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
                ForEach(model.reports) { report in
                    ReportRow(report: report)
                        .swipeActions {
                            if report.userID != nil && report.userID == session.userID || isAdmin {
                                Button(role: .destructive) { deleting = .report(report) } label: {
                                    Label(L10n.t("detail.delete"), systemImage: "trash")
                                }
                            }
                        }
                    if session.isSignedIn {
                        HStack(spacing: 16) {
                            Button {
                                like(report)
                            } label: {
                                Label("\(report.likes ?? 0)", systemImage: report.likedByMe == true ? "heart.fill" : "heart")
                            }
                            .accessibilityLabel(L10n.t(report.likedByMe == true ? "report.unlike" : "report.like"))
                            if canEdit(report) {
                                Button(L10n.t("detail.edit")) { editingReport = report }
                            }
                            // Replies hang from the first message: one level, as on the web.
                            if report.parentID == nil {
                                Button(L10n.t("report.reply")) { reportTarget = ReportTarget(replyTo: report) }
                            }
                            if report.isIncident == true, report.parentID == nil, canResolve(report) {
                                Button(L10n.t(report.resolvedAt == nil ? "report.resolve" : "report.reopen")) { resolve(report) }
                            }
                        }
                        .buttonStyle(.borderless)
                        .font(.footnote)
                        .padding(.leading, report.parentID == nil ? 0 : 16)
                    }
                }
                Button {
                    if session.isSignedIn { reportTarget = ReportTarget(replyTo: nil) } else { showsSignIn = true }
                } label: {
                    Label(L10n.t("report.add"), systemImage: "exclamationmark.bubble")
                }
                .frame(minHeight: 44)
            }
            MaintenanceSection(font: font, capabilities: capabilities, isModerator: session.isStaff,
                               onChanged: { await model.load() }, onNotice: { notice = $0 })
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

    /// The status, how much to trust it and when, in one row: what the short card has room for.
    private func statusRow(_ font: FontDetail) -> some View {
        let evidence = model.evidence(for: font)
        let level = Confidence.level(of: evidence)
        return Group {
            HStack(spacing: 8) {
                if let status = WaterStatus(evidence.lastWaterStatus) {
                    StatusBadge(status: status)
                }
                Text("\(level.emoji) \(L10n.t(level.labelKey))")
                    .font(.subheadline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if let date = evidence.lastUpdate {
                    Text(RelativeTime.string(since: date))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// What the one-line status means, for whoever doubts it: below the short card.
    private func statusSection(_ font: FontDetail) -> some View {
        let evidence = model.evidence(for: font)
        let level = Confidence.level(of: evidence)
        // A stale status is still shown, but not as the current one.
        let title = level == .stale ? "detail.lastReportedStatus" : "detail.currentStatus"
        return Section(L10n.t(title)) {
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
                           value: font.source?.emojiLabel ?? L10n.t("detail.unknownType"))
            LabeledContent(label("detail.drinkability"),
                           value: font.drinkable?.emojiLabel ?? L10n.t("detail.unknownDrink"))
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
extension EnvironmentValues {
    /// Goes to the map and shows a fountain there. `nil` where the page is already over
    /// the map, so "view on map" is not offered.
    @Entry var showOnMap: ((FontSummary) -> Void)? = nil
}

/// A round action of the place card, 48 pt, the web's thumb size.
private struct CircleIcon: View {
    let systemImage: String
    var color: Color = .primary

    var body: some View {
        Image(systemName: systemImage)
            .font(.body.weight(.semibold))
            .foregroundStyle(color)
            .frame(width: 48, height: 48)
            .contentShape(Circle())
    }
}

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
            .lineLimit(1)
            .fixedSize()
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
                if let user = review.username { UserLink(username: user) } else { Text(L10n.t("review.anon")) }
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
            HStack(spacing: 4) {
                if let user = report.username { UserLink(username: user) } else { Text(L10n.t("review.anon")) }
                if report.editedAt != nil { Text("· " + L10n.t("report.edited")) }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(.leading, report.parentID == nil ? 0 : 16)
        .padding(.vertical, 4)
    }
}
