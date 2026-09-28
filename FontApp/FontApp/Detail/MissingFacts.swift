import SwiftUI

/// What a fountain's page lacks and a passer-by can tell in one tap. Three of four
/// imported fountains have no name, and many no kind or drinkability: asking for the
/// whole edit form hides that; asking for the one thing missing gets it filled.
nonisolated enum MissingFact: String, Sendable {
    // In order of value: drinkability decides whether someone drinks.
    case drinkable, source, name

    static func all(of font: FontDetail) -> [MissingFact] {
        var out: [MissingFact] = []
        if font.drinkable == nil { out.append(.drinkable) }
        if font.source == nil { out.append(.source) }
        if font.name?.isEmpty ?? true { out.append(.name) }
        return out
    }
}

/// Saves one fact on its own. The server's edit is whole-fountain (`PUT /fonts/:id`), so
/// everything else goes as it is; editing is open to any account, as a wiki, and shows
/// at once (it stays in the fountain's history).
enum FactWriter {
    static func save(_ font: FontDetail, change: (inout NewFont) -> Void) async throws {
        var payload = NewFont(name: font.name, latitude: font.latitude, longitude: font.longitude,
                              image: font.image, description: font.description,
                              source: font.source, drinkable: font.drinkable)
        change(&payload)
        guard let token = APIClient.shared.credentials.current else {
            throw APIError(status: 401, reason: nil, code: nil, retryAfter: nil)
        }
        _ = try await APIClient.shared.updateFont(font.id, payload, token: token)
        NotificationCenter.default.post(name: .fontChanged, object: font.id)
    }
}

/// Fountains already asked about, per account: one question per fountain and person,
/// ever. "I don't know" or ignoring it is an answer too.
enum FollowUpAsked {
    private static func key(_ user: UUID) -> String { "fill.asked.\(user.uuidString)" }

    static func contains(_ font: UUID, user: UUID, _ defaults: UserDefaults = .standard) -> Bool {
        (defaults.stringArray(forKey: key(user)) ?? []).contains(font.uuidString)
    }

    static func insert(_ font: UUID, user: UUID, _ defaults: UserDefaults = .standard) {
        var list = defaults.stringArray(forKey: key(user)) ?? []
        guard !list.contains(font.uuidString) else { return }
        list.append(font.uuidString)
        // A bound, not a history: the oldest go first.
        defaults.set(Array(list.suffix(2000)), forKey: key(user))
    }
}

/// Right after a quick review, under the chips: one question, answered in one tap, about
/// the most valuable thing missing. Not a popup — after contributing that feels like a
/// toll, and it would cover the undo.
struct FollowUpQuestion: View {
    let font: FontDetail
    let fact: MissingFact
    let onAnswered: (Bool) -> Void

    @State private var name = ""
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.t("ios.fill.ask.\(fact.rawValue)")).font(.headline)
                switch fact {
                case .drinkable:
                    chips(Drinkable.allCases.map { ($0.emojiLabel, $0) }) { value in
                        await save { $0.drinkable = value }
                    }
                case .source:
                    chips(WaterSource.allCases.map { ($0.emojiLabel, $0) }) { value in
                        await save { $0.source = value }
                    }
                case .name:
                    HStack {
                        TextField(L10n.t("ios.fill.namePlaceholder"), text: $name)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .onSubmit { Task { await saveName() } }
                        Button(L10n.t("form.save")) { Task { await saveName() } }
                            .buttonStyle(.borderedProminent)
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                    }
                }
                Button(L10n.t("ios.fill.dontKnow")) { onAnswered(false) }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 44)
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }
            }
            .padding(.vertical, 4)
            .disabled(saving)
        }
    }

    private func chips<T>(_ options: [(String, T)], pick: @escaping (T) async -> Void) -> some View {
        FlowLayout(spacing: 8) {
            ForEach(options.indices, id: \.self) { i in
                Button { Task { await pick(options[i].1) } } label: {
                    Text(options[i].0).font(.subheadline)
                        .padding(.horizontal, 12).frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            }
        }
    }

    private func saveName() async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await save { $0.name = trimmed }
    }

    private func save(_ change: (inout NewFont) -> Void) async {
        saving = true
        defer { saving = false }
        do {
            try await FactWriter.save(font, change: change)
            onAnswered(true)
        } catch {
            self.error = ErrorText.describe(error)
        }
    }
}

/// A row for an empty fact: "Add drinkability" in colour instead of "— unknown —",
/// filling that one field in place instead of the whole form.
struct MissingFactRow: View {
    let font: FontDetail
    let fact: MissingFact
    let label: String
    let onSaved: () -> Void
    let onSignIn: (() -> Void)?

    @State private var naming = false
    @State private var name = ""
    @State private var error: String?

    var body: some View {
        LabeledContent(label) {
            if let onSignIn {
                Button(L10n.t("ios.fill.add.\(fact.rawValue)"), action: onSignIn).buttonStyle(.borderless)
            } else {
                switch fact {
                case .drinkable:
                    Menu(L10n.t("ios.fill.add.drinkable")) {
                        ForEach(Drinkable.allCases, id: \.self) { d in
                            Button(d.emojiLabel) { save { $0.drinkable = d } }
                        }
                    }
                case .source:
                    Menu(L10n.t("ios.fill.add.source")) {
                        ForEach(WaterSource.allCases, id: \.self) { s in
                            Button(s.emojiLabel) { save { $0.source = s } }
                        }
                    }
                case .name:
                    Button(L10n.t("ios.fill.add.name")) { naming = true }.buttonStyle(.borderless)
                }
            }
        }
        .alert(L10n.t("ios.fill.ask.name"), isPresented: $naming) {
            // A proper name, often Catalan on an English keyboard: no autocorrection.
            TextField(L10n.t("ios.fill.namePlaceholder"), text: $name)
                .autocorrectionDisabled()
            Button(L10n.t("form.save")) {
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { save { $0.name = trimmed } }
            }
            Button(L10n.t("form.cancel"), role: .cancel) {}
        }
        .alert(error ?? "", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }

    private func save(_ change: @escaping (inout NewFont) -> Void) {
        Task {
            do {
                try await FactWriter.save(font, change: change)
                onSaved()
            } catch {
                self.error = ErrorText.describe(error)
            }
        }
    }
}

/// Chips that wrap onto the next line, as the web's.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += row + spacing; row = 0 }
            x += size.width + spacing
            row = max(row, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, width), height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += row + spacing; row = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}
