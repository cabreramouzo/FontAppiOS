import SwiftUI

/// Why a page is not on the map, said to everyone who reaches it (an old link, search):
/// otherwise the page looks normal while the pin shows nowhere. Saying it is half the
/// point of hiding instead of deleting.
struct HiddenNotice: View {
    let font: FontDetail

    var body: some View {
        if let good = font.duplicateOf {
            notice("hidden.duplicateTitle", "hidden.duplicateBody") {
                NavigationLink(L10n.t("hidden.goToGood")) { FontDetailView(fontID: good) }
            }
        } else if font.retiredAt != nil {
            notice("hidden.retiredTitle", "hidden.retiredBody") { EmptyView() }
        } else if let state = font.moderationState, state != "visible" {
            notice(state == "pending" ? "hidden.pendingTitle" : "hidden.moderationTitle",
                   state == "pending" ? "hidden.pendingBody" : "hidden.moderationBody") { EmptyView() }
        }
    }

    private func notice(_ title: String, _ body: String, @ViewBuilder link: () -> some View) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Label(L10n.t(title), systemImage: "eye.slash").font(.headline).foregroundStyle(.orange)
                Text(L10n.t(body)).font(.subheadline)
            }
            link()
        }
    }
}

/// Map maintenance, what levels 4 to 6 and moderators can do on one fountain: history,
/// mark as a copy, retire, hide for abuse. At the end and apart, because it is not for
/// whoever comes to drink; and only drawn when you have at least one of them.
struct MaintenanceSection: View {
    let font: FontDetail
    let capabilities: Set<String>
    let isModerator: Bool
    let onChanged: () async -> Void
    let onNotice: (String) -> Void
    /// Opens the choice of the fountain this one copies. The page presents it: a sheet
    /// hung on a row of the list was raised by SwiftUI over the map instead, replacing
    /// the fountain's own sheet, which closed both a second later.
    let onMarkDuplicate: () -> Void

    @State private var confirmsRetire = false
    @State private var hidesForAbuse = false
    @State private var isBusy = false

    private var canHistory: Bool { capabilities.contains("viewFontHistory") }
    private var canDuplicate: Bool { capabilities.contains("markDuplicate") }
    private var canRetire: Bool { capabilities.contains("retireFont") }

    var body: some View {
        if canHistory || canDuplicate || canRetire || isModerator {
            Section(L10n.t("maint.title")) {
                if canHistory {
                    NavigationLink {
                        FontHistoryScreen(fontID: font.id)
                    } label: {
                        Label(L10n.t("maint.history"), systemImage: "clock.arrow.circlepath")
                    }
                }
                if canDuplicate {
                    if font.duplicateOf != nil {
                        action("maint.undoDuplicate", "arrow.uturn.backward") {
                            try await APIClient.shared.markDuplicate(font.id, of: nil)
                        }
                    } else {
                        Button(action: onMarkDuplicate) {
                            Label(L10n.t("maint.markDuplicate"), systemImage: "square.on.square")
                        }
                    }
                }
                if canRetire {
                    if font.retiredAt != nil {
                        action("maint.undoRetire", "arrow.uturn.backward") {
                            try await APIClient.shared.retireFont(font.id, false)
                        }
                    } else {
                        Button(role: .destructive) { confirmsRetire = true } label: {
                            Label(L10n.t("maint.retire"), systemImage: "mappin.slash")
                        }
                        .confirmsDestructive(L10n.t("maint.confirmRetire"), isPresented: $confirmsRetire,
                                             action: L10n.t("maint.retire")) {
                            run { try await APIClient.shared.retireFont(font.id, true) }
                        }
                    }
                }
                if isModerator {
                    if let state = font.moderationState, state != "visible" {
                        action("maint.restoreAbuse", "eye") {
                            try await APIClient.shared.hideForAbuse(font.id, reason: nil)
                        }
                    } else {
                        Button(role: .destructive) { hidesForAbuse = true } label: {
                            Label(L10n.t("maint.hideAbuse"), systemImage: "exclamationmark.octagon")
                        }
                        .confirmationDialog(L10n.t("maint.abuseTitle"), isPresented: $hidesForAbuse, titleVisibility: .visible) {
                            ForEach(["spam", "fake", "abuse"], id: \.self) { reason in
                                Button(L10n.t("maint.abuse.\(reason)"), role: .destructive) {
                                    run { try await APIClient.shared.hideForAbuse(font.id, reason: reason) }
                                }
                            }
                            Button(L10n.t("form.cancel"), role: .cancel) {}
                        } message: {
                            Text(L10n.t("maint.abuseHelp"))
                        }
                    }
                }
            }
            .disabled(isBusy)
        }
    }

    private func action(_ key: String, _ icon: String, _ work: @escaping () async throws -> Void) -> some View {
        Button { run(work) } label: { Label(L10n.t(key), systemImage: icon) }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                try await work()
                NotificationCenter.default.post(name: .fontChanged, object: font.id)
                await onChanged()
            } catch {
                onNotice(ErrorText.describe(error))
            }
        }
    }
}

/// Who changed what, field by field; only what changed.
struct FontHistoryScreen: View {
    let fontID: UUID
    @State private var entries: [FontEditEntry]?
    @State private var error: String?

    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.red) }
            if let entries {
                if entries.isEmpty { Text(L10n.t("maint.noHistory")).foregroundStyle(.secondary) }
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(entry.editorName.map { "@\($0)" } ?? L10n.t("review.anon")) · \(RelativeTime.string(since: entry.createdAt))")
                            .font(.footnote).foregroundStyle(.secondary)
                        ForEach(changes(entry), id: \.0) { field, before, after in
                            (Text("\(L10n.t("maint.field.\(field)")): ").bold()
                             + Text(before).strikethrough().foregroundStyle(.secondary)
                             + Text(" → \(after)"))
                                .font(.subheadline)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } else if error == nil {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(L10n.t("maint.history"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do { entries = try await APIClient.shared.fontHistory(fontID) } catch { self.error = ErrorText.describe(error) }
        }
    }

    private func changes(_ e: FontEditEntry) -> [(String, String, String)] {
        [("name", e.before.name, e.after.name), ("description", e.before.description, e.after.description),
         ("source", e.before.source, e.after.source), ("drinkable", e.before.drinkable, e.after.drinkable)]
            .filter { $0.1 != $0.2 }
            .map { ($0.0, $0.1 ?? "—", $0.2 ?? "—") }
    }
}
