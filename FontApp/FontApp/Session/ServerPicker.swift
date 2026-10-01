#if DEBUG
import SwiftUI

/// Debug builds only: the server the app talks to, as an editable field that starts with the
/// one in use, so the same build can go against the local backend or production.
///
/// It applies on the next launch: the session, its token (one per host, see `TokenKeychain`),
/// the cached reads and the outbox are all built around one server for the life of the app.
/// Saved pins and zones of the other server are not told apart; reviews and photos sent to
/// production are real.
struct ServerPicker: View {
    @State private var text = APIEnvironment.baseURL.absoluteString
    @State private var saved = false

    private var parsed: URL? { APIEnvironment.server(from: text) }
    private var changed: Bool { parsed != nil && parsed != APIEnvironment.baseURL }

    var body: some View {
        Section {
            TextField(text: $text, prompt: Text(verbatim: "https://…")) { Text(verbatim: "API server") }
                .font(.callout.monospaced())
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit(apply)
                .onChange(of: text) { saved = false }
            HStack {
                Button("Production") { text = APIEnvironment.production.absoluteString }
                Spacer()
                Button("Local") { text = APIEnvironment.local.absoluteString }
                Spacer()
                Button("Apply", action: apply).bold().disabled(!changed)
            }
            .buttonStyle(.borderless)
            .frame(minHeight: 44)
        } header: {
            Text(verbatim: "Debug · API server")
        } footer: {
            if saved {
                Text(verbatim: "Saved. Close the app and open it again to use \(parsed?.absoluteString ?? "it").")
            } else if parsed == nil {
                Text(verbatim: "Not an address: use a URL, local or production.")
            } else {
                Text(verbatim: "In use: \(APIEnvironment.baseURL.absoluteString)")
            }
        }
    }

    private func apply() {
        guard let url = parsed else { return }
        APIEnvironment.choose(url)
        saved = true
    }
}
#endif
