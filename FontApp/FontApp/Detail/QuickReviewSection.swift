import SwiftUI

/// "How is it now?" with the three chips, the thanks and a 10-second undo.
/// Without a session there is nothing to tap, only a way to sign in.
struct QuickReviewSection: View {
    @Bindable var model: QuickReviewModel
    /// Reloads the fountain after a review lands or is undone.
    let onChange: () async -> Void
    /// Presented by the page, not from inside the list: a sheet hung on a lazy list
    /// section dismissed the whole fountain sheet instead.
    let onSignIn: () -> Void

    @Environment(SessionStore.self) private var session
    @Environment(LocationService.self) private var location

    var body: some View {
        Section(L10n.t("popup.howIsIt")) {
            if session.isSignedIn {
                chips
                feedback
            } else {
                Button(L10n.t("nav.enter"), action: onSignIn)
                    .frame(minHeight: 44)
                Text(L10n.t("ios.signInPrompt")).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var chips: some View {
        HStack(spacing: 8) {
            ForEach(QuickReviewModel.chips, id: \.self) { status in
                Button {
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
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.bordered)
                // Staff contribute in purple so it is never done as staff by mistake.
                .tint(session.isStaff ? Color.staff : status.color)
                .disabled(isSending)
            }
        }
        .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
    }

    @ViewBuilder private var feedback: some View {
        switch model.state {
        case .sent(_, let confirmedInstead, _):
            HStack {
                Text(L10n.t(confirmedInstead ? "popup.confirmedThanks" : "popup.thanks"))
                    .font(.subheadline)
                Spacer()
                if model.canUndo {
                    Button(L10n.t("popup.undo")) {
                        Task { if await model.undo() { await onChange() } }
                    }
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
