import SwiftUI

/// A comment about a fountain, optionally marked as an incident that someone has to fix,
/// or a reply to one. Marking it is an explicit gesture, as on the web: otherwise the box
/// fills with things nobody will ever resolve. A reply is never an incident.
struct ReportSheet: View {
    let fontID: UUID
    /// Replying to this comment, or a new one.
    var replyTo: ReportResponse?
    /// Correcting your own note's text, within the hour.
    var editing: ReportResponse?
    let onPosted: () async -> Void

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var draft = Draft()
    @State private var isSending = false
    @State private var error: String?

    static let kinds = ["broken", "dry", "dirty", "access", "other"]

    struct Draft: Codable, Equatable {
        var message = ""
        var isIncident = false
        var kind = "other"
    }

    private var draftKey: String {
        FormDraft.key(replyTo.map { "reply.\($0.id.uuidString)" } ?? "comment", user: session.userID, font: fontID)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
                if let replyTo {
                    Section {
                        Text(replyTo.message).font(.footnote).foregroundStyle(.secondary).lineLimit(4)
                    }
                }
                Section {
                    MentionField(placeholder: L10n.t(replyTo == nil ? "comment.placeholder" : "report.replyPlaceholder"),
                                 text: $draft.message)
                }
                if replyTo == nil, editing == nil {
                    Section {
                        Toggle(L10n.t("comment.isIncident"), isOn: $draft.isIncident)
                        if draft.isIncident {
                            Picker(L10n.t("comment.isIncident"), selection: $draft.kind) {
                                ForEach(Self.kinds, id: \.self) { Text(L10n.t("incident.\($0)")).tag($0) }
                            }
                            .pickerStyle(.inline)
                            .labelsHidden()
                        }
                    }
                }
            }
            .navigationTitle(L10n.t(editing != nil ? "detail.edit" : replyTo == nil ? "report.add" : "report.reply"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSending {
                        ProgressView()
                    } else {
                        Button(L10n.t(editing != nil ? "form.save" : replyTo == nil ? "comment.submit" : "report.send"), action: send)
                            .disabled(draft.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .onAppear {
                if let editing {
                    draft = Draft(message: editing.message)
                } else {
                    draft = FormDraft.load(Draft.self, key: draftKey) ?? Draft()
                }
            }
            .onChange(of: draft) {
                if editing == nil { FormDraft.save(draft.message.isEmpty ? nil : draft, key: draftKey) }
            }
        }
    }

    private func send() {
        isSending = true
        error = nil
        let incident = replyTo == nil && draft.isIncident
        let report = NewReport(message: draft.message.trimmingCharacters(in: .whitespacesAndNewlines),
                               isIncident: incident, incidentKind: incident ? draft.kind : nil,
                               parentID: replyTo?.id)
        Task {
            defer { isSending = false }
            do {
                if let editing {
                    _ = try await APIClient.shared.updateReport(editing.id, on: fontID, message: report.message)
                } else {
                    _ = try await APIClient.shared.postReport(on: fontID, report)
                }
                FormDraft.save(Draft?.none, key: draftKey)
                await onPosted()
                dismiss()
            } catch {
                self.error = ErrorText.describe(error)
            }
        }
    }
}
