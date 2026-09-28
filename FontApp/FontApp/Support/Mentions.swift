import SwiftUI

/// `@mentions` in what people write. The same rule as the server (`Utils/Mentions.swift`)
/// and the web (`lib/mentions.ts`): if they differ, the app underlines people nobody
/// notifies, or notifies people the screen does not show as mentioned.
nonisolated enum Mentions {
    /// `(?<![\w@.])`: `hola@fontapp.net` mentions nobody.
    static let pattern = try! NSRegularExpression(pattern: "(?<![\\w@.])@([a-zA-Z0-9_.-]{3,30})")
    private static let inProgress = try! NSRegularExpression(pattern: "(?<![\\w@.])@([a-zA-Z0-9_.-]{0,30})$")

    /// Character ranges (offsets) of each mention, `@` included, and the name.
    static func matches(in text: String) -> [(range: Range<Int>, name: String)] {
        let ns = text as NSString
        return pattern.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            guard let whole = Range(m.range, in: text), let name = Range(m.range(at: 1), in: text) else { return nil }
            let start = text.distance(from: text.startIndex, to: whole.lowerBound)
            return (start..<start + text[whole].count, String(text[name]))
        }
    }

    /// The mention being typed at the caret (a character offset): where it starts and
    /// what is typed so far. Nil when the caret is inside a word already written.
    struct Typing: Equatable { let from: Int; let to: Int; let prefix: String }

    static func typing(in text: String, caret: Int) -> Typing? {
        let chars = Array(text)
        guard caret <= chars.count else { return nil }
        let left = String(chars[..<caret])
        let ns = left as NSString
        guard let m = inProgress.firstMatch(in: left, range: NSRange(location: 0, length: ns.length)),
              let whole = Range(m.range, in: left), let prefix = Range(m.range(at: 1), in: left) else { return nil }
        if caret < chars.count, String(chars[caret]).range(of: "^[a-zA-Z0-9_.-]$", options: .regularExpression) != nil {
            return nil
        }
        return Typing(from: caret - left[whole].count, to: caret, prefix: String(left[prefix]))
    }

    /// The text with the mention replaced by the chosen name and a space, and the caret
    /// after it: without the space, the next letter would lengthen the name.
    static func insert(_ username: String, in text: String, at typing: Typing) -> (text: String, caret: Int) {
        let chars = Array(text)
        let piece = "@\(username) "
        return (String(chars[..<typing.from]) + piece + String(chars[typing.to...]), typing.from + piece.count)
    }

    /// Text with each mention as a link that opens the profile (`openProfile`).
    static func linked(_ text: String) -> AttributedString {
        var out = AttributedString(text)
        for m in matches(in: text) {
            let lower = out.characters.index(out.startIndex, offsetBy: m.range.lowerBound)
            let upper = out.characters.index(out.startIndex, offsetBy: m.range.upperBound)
            out[lower..<upper].link = URL(string: "fontapp-user:\(m.name)")
            out[lower..<upper].foregroundColor = .accentColor
        }
        return out
    }
}

/// A text written by someone, with its @mentions coloured and opening the profile.
struct MentionText: View {
    let text: String
    @Environment(\.openProfile) private var openProfile

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(Mentions.linked(text))
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == "fontapp-user", let openProfile else { return .systemAction }
                openProfile(url.absoluteString.replacingOccurrences(of: "fontapp-user:", with: ""))
                return .handled
            })
    }
}

/// A text box that suggests `@names` as they are typed (two letters at least: with one,
/// the list is the census in alphabetical order), and colours each mention once written,
/// as a sign it is a link.
struct MentionField: View {
    let placeholder: String
    @Binding var text: String

    @State private var rich = AttributedString()
    @State private var selection = AttributedTextSelection()
    @State private var suggestions: [String] = []
    @State private var typing: Mentions.Typing?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder).foregroundStyle(.tertiary).padding(.top, 8).padding(.leading, 5)
                        .accessibilityHidden(true)
                }
                TextEditor(text: $rich, selection: $selection)
                    .frame(minHeight: 72)
                    .scrollContentBackground(.hidden)
                    .accessibilityLabel(placeholder)
            }
            if !suggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(suggestions, id: \.self) { name in
                        Button { choose(name) } label: {
                            Text(verbatim: "@\(name)").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        if name != suggestions.last { Divider() }
                    }
                }
                .padding(.horizontal, 12)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .onAppear { if String(rich.characters) != text { rich = styled(text) } }
        .onChange(of: rich) { _, new in
            let plain = String(new.characters)
            if plain != text { text = plain }
            // Colour only when the colouring changed: rewriting the text on every
            // keystroke would move the caret.
            let restyled = styled(plain)
            if restyled != new { rich = restyled }
            typing = Mentions.typing(in: plain, caret: caret(in: new))
        }
        .onChange(of: text) { _, new in if new != String(rich.characters) { rich = styled(new) } }
        .task(id: typing) {
            guard let typing, typing.prefix.count >= 2 else { suggestions = []; return }
            // A breath before asking: typing "maria" would otherwise fire four requests.
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            suggestions = (try? await APIClient.shared.searchMentions(typing.prefix)) ?? []
        }
    }

    private func caret(in string: AttributedString) -> Int {
        switch selection.indices(in: string) {
        case .insertionPoint(let i): string.characters.distance(from: string.startIndex, to: i)
        case .ranges(let set): set.ranges.last.map { string.characters.distance(from: string.startIndex, to: $0.upperBound) }
            ?? string.characters.count
        }
    }

    private func styled(_ plain: String) -> AttributedString {
        var out = AttributedString(plain)
        for m in Mentions.matches(in: plain) {
            let lower = out.characters.index(out.startIndex, offsetBy: m.range.lowerBound)
            let upper = out.characters.index(out.startIndex, offsetBy: m.range.upperBound)
            out[lower..<upper].foregroundColor = .accentColor
        }
        return out
    }

    private func choose(_ name: String) {
        guard let typing else { return }
        let result = Mentions.insert(name, in: text, at: typing)
        text = result.text
        let new = styled(result.text)
        rich = new
        selection = AttributedTextSelection(insertionPoint: new.characters.index(new.startIndex, offsetBy: result.caret))
        suggestions = []
        self.typing = nil
    }
}
