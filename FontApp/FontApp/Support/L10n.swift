import Foundation

/// Texts shared with the web app.
///
/// `Localizable.xcstrings` is generated from `web/src/i18n/dictionaries.ts` by
/// `scripts/sync-strings.mjs`, keeping the web keys and its `{name}` placeholders.
nonisolated enum L10n {
    static func t(_ key: String, _ params: [String: CustomStringConvertible] = [:],
                  bundle: Bundle = .main) -> String {
        var text = bundle.localizedString(forKey: key, value: nil, table: nil)
        for (name, value) in params {
            text = text.replacingOccurrences(of: "{\(name)}", with: value.description)
        }
        return text
    }

    /// The translation, or `nil` when the key is missing. `localizedString` returns the
    /// key itself when it cannot find one, and a raw key must never reach the screen.
    static func lookup(_ key: String, bundle: Bundle = .main) -> String? {
        let text = bundle.localizedString(forKey: key, value: nil, table: nil)
        return text == key ? nil : text
    }

    /// A fountain's display name. Names are never translated or invented: an imported
    /// point without one reads "unnamed fountain" in the reader's language.
    static func fontName(_ name: String?) -> String {
        if let name, !name.trimmingCharacters(in: .whitespaces).isEmpty { return name }
        return t("font.unnamed")
    }
}
