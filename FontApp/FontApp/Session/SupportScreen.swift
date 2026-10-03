import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins

/// Invite people first, then feedback, then voluntary support, as on the PWA.
struct SupportScreen: View {
    @State private var showsFeedback = false
    @State private var copied = false
    @State private var showsQR = false

    private let invite = URL(string: "https://fontapp.net/?p=amigos")!
    private let aixeta = URL(string: "https://fontapp.aixeta.cat/")!
    private let bitcoinAddress = "bc1qu29jxn37wwwrqz6f6qyrwsaa8xn72xy9wmeh0w"

    var body: some View {
        List {
            Section {
                Text(L10n.t("support.intro")).foregroundStyle(.secondary)
            }
            Section {
                Text(L10n.t("support.inviteBody"))
                ShareLink(item: invite, subject: Text("FontApp"), message: Text(L10n.t("support.shareText"))) {
                    Label(L10n.t("support.share"), systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .fullSeparator()
                }
                Link(destination: URL(string: "https://wa.me/?text=\(shareText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")!) {
                    Label(L10n.t("support.whatsapp"), systemImage: "message")
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .fullSeparator()
                }
            } header: { Text(L10n.t("support.inviteTitle")) }
            Section {
                Text(L10n.t("support.feedbackBody"))
                Button { showsFeedback = true } label: {
                    Label(L10n.t("support.feedbackCta"), systemImage: "bubble.left")
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .fullSeparator()
                }
            } header: { Text(L10n.t("support.feedbackTitle")) }
            Section {
                Text(L10n.t("support.costsBody"))
                Link(destination: aixeta) {
                    Label(L10n.t("donate.aixeta"), systemImage: "heart")
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .fullSeparator()
                }
                Text(L10n.t("donate.monthly") + " · " + L10n.t("donate.flexibleAmount"))
                    .font(.footnote).foregroundStyle(.secondary)
                // The address itself, so people can check it; tapping it copies it.
                Button {
                    UIPasteboard.general.string = bitcoinAddress
                    copied = true
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(L10n.t("donate.btcLabel"))
                            Spacer()
                            Label(copied ? L10n.t("donate.copied") : L10n.t("donate.copy"),
                                  systemImage: copied ? "checkmark" : "doc.on.doc")
                                .font(.callout)
                        }
                        Text(verbatim: bitcoinAddress)
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(minHeight: 44)
                }
                // A BIP 21 URI, which every wallet reads when scanning.
                if let qr = QRCode.image(for: "bitcoin:\(bitcoinAddress)") {
                    DisclosureGroup(isExpanded: $showsQR) {
                        Image(uiImage: qr)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 180, height: 180)
                            .padding(8)
                            .background(.white, in: .rect(cornerRadius: 8))
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel(L10n.t("donate.btcLabel"))
                    } label: {
                        Label(L10n.t("ios.donate.qr"), systemImage: "qrcode")
                            .frame(minHeight: 44)
                    }
                }
            } header: { Text(L10n.t("support.costsTitle")) }
        }
        .navigationTitle(L10n.t("support.title"))
        .sheet(isPresented: $showsFeedback) { FeedbackSheet() }
    }

    private var shareText: String {
        "\(L10n.t("support.shareText")) https://fontapp.net/?p=amigos"
    }
}

private struct FeedbackSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    @State private var country = ""
    @State private var email = ""
    @State private var sending = false
    @State private var sent = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                if sent {
                    Section { Label(L10n.t("feedback.thanks"), systemImage: "checkmark.circle.fill") }
                } else {
                    Section {
                        Text(L10n.t("feedback.intro")).font(.subheadline).foregroundStyle(.secondary)
                        TextField(L10n.t("feedback.message"), text: $message, axis: .vertical)
                            .lineLimit(3...8)
                        TextField(L10n.t("feedback.country"), text: $country)
                        TextField(L10n.t("feedback.email"), text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                    }
                    if let error { Section { Text(error).foregroundStyle(.red) } }
                }
            }
            .navigationTitle(L10n.t("feedback.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
                if !sent {
                    ToolbarItem(placement: .confirmationAction) {
                        if sending { ProgressView() }
                        else { Button(L10n.t("feedback.submit")) { Task { await submit() } }
                            .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || message.count > 2000) }
                    }
                }
            }
        }
    }

    private func submit() async {
        sending = true
        defer { sending = false }
        do {
            try await APIClient.shared.sendFeedback(
                message: message.trimmingCharacters(in: .whitespacesAndNewlines),
                country: country.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                email: email.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty)
            sent = true
            error = nil
        } catch { self.error = ErrorText.describe(error) }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

private enum QRCode {
    static func image(for text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}


private extension View {
    /// A centred row would start its separator mid-row; run it from the row's leading edge.
    func fullSeparator() -> some View {
        alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }
}
