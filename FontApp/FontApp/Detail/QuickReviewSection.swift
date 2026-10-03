import SwiftUI
import TipKit

/// "How is it now?" with the three chips, the thanks and a 10-second undo.
/// Without a session the chips are still there, and tapping one asks to sign in: seeing
/// them is how people find out that anyone can say how a fountain is.
struct QuickReviewSection: View {
    @Bindable var model: QuickReviewModel
    /// Your own report is the latest and less than a day old: the same status again says
    /// nothing new; a different one does.
    let ownRecent: CommentResponse?
    /// Reloads the fountain after a review lands or is undone.
    let onChange: () async -> Void
    /// Presented by the page, not from inside the list: a sheet hung on a lazy list
    /// section dismissed the whole fountain sheet instead.
    let onSignIn: () -> Void
    /// The fountain, for the questions about what it lacks.
    var font: FontDetail? = nil
    /// What is still to ask once the status is said, first one showing (`QuickFlow`).
    var steps: [QuickFlow.Step] = []
    /// The page's photo model, for the photo step and its thanks.
    var photo: PhotoUploadModel? = nil
    var onCamera: () -> Void = {}
    /// The current step is done: answered (true) or skipped (false).
    var onStep: (Bool) -> Void = { _ in }

    @Environment(SessionStore.self) private var session
    @Environment(LocationService.self) private var location

    var body: some View {
        Section {
            // Once said, the chips give way to the thanks, as in the web popup: one tap is
            // one review, and a second tap cannot publish a twin. Undoing brings them back.
            if !model.hasSpoken {
                // In the chips' row: a tip of its own would leave an empty row once seen.
                VStack(spacing: 10) {
                    TipView(QuickReviewTip())
                    chips
                }
                .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
                // Your own fresh report: its chip is already said (a twin adds nothing),
                // but a change is news and stays one tap away, as the full form allows.
                if let ownRecent, ownStatus != nil {
                    Text(L10n.t("ios.quick.youSaid", ["when": RelativeTime.string(since: ownRecent.createdAt)]))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            if session.isSignedIn {
                // Only when there is something to show: an empty slot is still a list row,
                // a blank strip with a separator under the chips.
                if hasSlot {
                    // One slot that changes, not rows added under it: each question used to
                    // land below the short card, where nobody saw it (field test, 02/10/2026).
                    VStack(alignment: .leading, spacing: 10) {
                        feedback
                        // Landed online: the moment to say it would have worked offline too.
                        if case .sent = model.state { TipView(OfflineReviewTip()) }
                        if showsSteps, let step = steps.first {
                            stepView(step)
                                .id(step)
                                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                        removal: .opacity))
                        }
                    }
                    .animation(.snappy, value: steps.first)
                    .sensoryFeedback(.selection, trigger: steps.first)
                }
            } else {
                Text(L10n.t("ios.signInPrompt")).font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            // Answered, with a question in the slot: the title is a line the card lacks.
            if !(showsSteps && !steps.isEmpty) { Text(L10n.t("popup.howIsIt")) }
        }
    }

    private var chips: some View {
        HStack(spacing: 8) {
            ForEach(QuickReviewModel.chips, id: \.self) { status in
                Button {
                    guard session.isSignedIn else { onSignIn(); return }
                    // The position only counts if permission was already given.
                    let fix = location.isAuthorized ? location.location : nil
                    Task { if await model.tap(status, fix: fix) { await onChange() } }
                } label: {
                    VStack(spacing: 2) {
                        if model.state == .sending(status) {
                            ProgressView()
                        } else {
                            Text(status.emoji)
                        }
                        Text(L10n.t(status.labelKey))
                            .font(.footnote.weight(.semibold))
                            // The tint on its own tinted fill was unreadable in dark mode;
                            // the emoji already carries the status.
                            .foregroundStyle(Color.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.bordered)
                // Staff contribute in purple so it is never done as staff by mistake.
                .tint(session.isStaff ? Color.staff : status.color)
                .disabled(isSending || status == ownStatus)
                .accessibilityAddTraits(status == ownStatus ? .isSelected : [])
            }
        }
        .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
    }

    @ViewBuilder private var feedback: some View {
        switch model.state {
        case .sent(_, let confirmedInstead, _):
            HStack {
                thanks(L10n.t(confirmedInstead ? "popup.confirmedThanks" : "popup.thanks"))
                Spacer()
                if model.canUndo {
                    Button(L10n.t("popup.undo")) {
                        Task { if await model.undo() { await onChange() } }
                    }
                    .buttonStyle(.borderless)
                    .frame(minHeight: 44)
                }
            }
        case .queued:
            HStack {
                thanks(L10n.t("offline.savedUpdate"))
                Spacer()
                if model.canUndo {
                    Button(L10n.t("popup.undo")) { Task { _ = await model.undo() } }
                        .buttonStyle(.borderless)
                        .frame(minHeight: 44)
                }
            }
        case .undone:
            Text(L10n.t("popup.undone")).font(.subheadline).foregroundStyle(.secondary)
        case .failed(let message):
            Text(message).font(.subheadline).foregroundStyle(.red)
        case .idle, .sending:
            EmptyView()
        }
    }

    /// After a review that landed or waits in the outbox: the moment to ask more, in front
    /// of the fountain, often without signal (a photo queues too).
    private var showsSteps: Bool {
        switch model.state {
        case .sent, .queued: true
        default: false
        }
    }

    @ViewBuilder private func stepView(_ step: QuickFlow.Step) -> some View {
        switch step {
        case .photo:
            if let photo {
                VStack(alignment: .leading, spacing: 6) {
                    question(L10n.t("popup.addPhoto")) { onStep(false) }
                    if photo.state == .uploading {
                        HStack {
                            ProgressView()
                            Text(L10n.t("ios.uploading")).foregroundStyle(.secondary)
                        }
                        .frame(minHeight: 44)
                    } else {
                        if case .failed(let message) = photo.state {
                            Text(message).font(.footnote).foregroundStyle(.red)
                        }
                        PhotoSourceButtons(model: photo, onUploaded: onChange, onCamera: onCamera)
                    }
                }
            }
        case .fact(let fact):
            if let font {
                FollowUpQuestion(font: font, fact: fact, onAnswered: onStep)
            }
        }
    }

    /// The question and its way out on one line: "Not now" beside it costs no height.
    private func question(_ text: String, skip: @escaping () -> Void) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text).font(.subheadline.weight(.semibold))
            Spacer(minLength: 8)
            Button(L10n.t("ios.quick.notNow"), action: skip)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .frame(minHeight: 44)
        }
    }

    /// The thanks, which becomes the photo's once one is on its way.
    private func thanks(_ text: String) -> some View {
        let shown: String = switch photo?.state {
        case .done: L10n.t("popup.photoThanks")
        case .queued: L10n.t("offline.savedPhoto")
        default: text
        }
        return Text(shown).font(.subheadline)
    }

    private var ownStatus: WaterStatus? {
        ownRecent?.waterStatus.flatMap(WaterStatus.init(rawValue:))
    }

    /// The slot under the chips has a thanks, an error or a question to show.
    private var hasSlot: Bool {
        switch model.state {
        case .idle, .sending: false
        default: true
        }
    }

    private var isSending: Bool {
        if case .sending = model.state { return true }
        return false
    }
}

extension View {
    /// "Have you seen it recently?", asked once per fountain when the position says the
    /// person is clearly far. Hung on the page for the same reason as the sign-in sheet.
    func remoteReviewAlert(_ model: QuickReviewModel?, onSent: @escaping () async -> Void) -> some View {
        let isPresented = Binding(
            get: { model?.remoteQuestion != nil },
            set: { if !$0 { model?.remoteQuestion = nil } })
        return alert(L10n.t("remote.title"), isPresented: isPresented, presenting: model?.remoteQuestion) { question in
            Button(L10n.t("remote.confirm")) {
                Task { if await model?.confirmRemote(question) == true { await onSent() } }
            }
            Button(L10n.t("remote.cancel"), role: .cancel) { model?.remoteQuestion = nil }
        } message: { question in
            Text(L10n.t("remote.body", ["km": RemoteReview.kmLabel(question.meters)]))
        }
    }
}

