import CoreLocation
import SwiftUI

/// "This is the same as that one", open to anyone signed in, as on the web. It hides
/// nothing: it goes as a comment to whoever can decide, and never counts as an incident.
struct DuplicateSheet: View {
    let font: FontDetail
    let onSent: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var candidates: [FontSummary]?
    @State private var error: String?
    @State private var sending: UUID?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(L10n.t("dup.help")).font(.footnote).foregroundStyle(.secondary)
                }
                if let error {
                    Text(error).foregroundStyle(.red)
                }
                if let candidates {
                    ForEach(candidates) { other in
                        Button {
                            send(other.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(L10n.fontName(other.name))
                                    Text(distance(to: other)).font(.footnote).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if sending == other.id { ProgressView() }
                            }
                            .frame(minHeight: 44)
                        }
                        .foregroundStyle(.primary)
                        .disabled(sending != nil)
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .navigationTitle(L10n.t("dup.suggest"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(role: .close) { dismiss() } }
            }
            .task {
                do {
                    let near = try await APIClient.shared.nearby(latitude: font.latitude, longitude: font.longitude, quantity: 11)
                    candidates = near.filter { $0.id != font.id }
                } catch {
                    self.error = ErrorText.describe(error)
                    candidates = []
                }
            }
        }
    }

    private func distance(to other: FontSummary) -> String {
        let meters = CLLocation(latitude: font.latitude, longitude: font.longitude)
            .distance(from: CLLocation(latitude: other.latitude, longitude: other.longitude))
        return Measurement(value: meters, unit: UnitLength.meters).formatted(.measurement(width: .abbreviated, usage: .road))
    }

    private func send(_ other: UUID) {
        sending = other
        Task {
            defer { sending = nil }
            do {
                try await APIClient.shared.suggestDuplicate(font.id, of: other, message: L10n.t("dup.message"))
                dismiss()
                onSent(L10n.t("dup.sent"))
            } catch {
                self.error = ErrorText.describe(error)
            }
        }
    }
}
