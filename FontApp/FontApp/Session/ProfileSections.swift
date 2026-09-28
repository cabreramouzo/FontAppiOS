import SwiftUI

/// Who you are: initials, name, @username and email, as the web's profile opens.
struct ProfileHeader: View {
    let user: UserResponse
    let staff: Bool

    var body: some View {
        HStack(spacing: 14) {
            Text(initials)
                .font(.title2.bold())
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(staff ? Color.staff : Color.accentColor, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(user.name).font(.headline)
                    if staff {
                        Text(L10n.t("staff.tag"))
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .foregroundStyle(.white)
                            .background(Color.staff, in: Capsule())
                    }
                }
                Text(verbatim: "@\(user.username)").foregroundStyle(.secondary)
                if let email = user.email {
                    Text(verbatim: email).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    /// First letters of the first two words, like the web's avatar.
    private var initials: String {
        let words = user.name.split(whereSeparator: \.isWhitespace).prefix(2)
        let letters = words.compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }
}

/// A list that shows its first six and a "see them all (N)" that opens the rest, as the
/// web's `ListaConTope`. Nothing yet reads the empty text; still loading, a spinner.
struct CappedSection<Item: Identifiable, Row: View>: View {
    let title: String
    let systemImage: String
    var hint: String?
    let empty: String
    let items: [Item]?
    @ViewBuilder let row: (Item) -> Row

    static var cap: Int { 6 }
    @State private var showsAll = false

    var body: some View {
        Section {
            if let items {
                if items.isEmpty {
                    Text(empty).foregroundStyle(.secondary)
                } else {
                    ForEach(showsAll ? items : Array(items.prefix(Self.cap))) { row($0) }
                    if items.count > Self.cap {
                        Button(showsAll ? L10n.t("guard.showLess") : L10n.t("guard.showAll", ["n": items.count])) {
                            withAnimation { showsAll.toggle() }
                        }
                        .frame(minHeight: 44)
                    }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        } header: {
            Label(title, systemImage: systemImage)
        } footer: {
            if let hint { Text(hint) }
        }
    }
}

/// A fountain in one of your lists: its kind, its name and where it is.
struct ProfileFontRow: View {
    let font: FontSummary

    var body: some View {
        NavigationLink(value: font.id) {
            HStack(spacing: 12) {
                Text(font.source?.emoji ?? "💧").font(.title3).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.fontName(font.name))
                    // The municipality, not the kind: the emoji already says that. Outside
                    // Spain it falls back to the region, and with neither it stays one line.
                    if let place = font.municipality ?? font.region {
                        Text(place).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(minHeight: 44)
        }
    }
}

/// One of your reviews: the fountain, the status you gave and what you wrote.
struct ProfileReviewRow: View {
    let comment: MyComment

    var body: some View {
        NavigationLink(value: comment.fontID) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.fontName(comment.fontName)).font(.subheadline.weight(.semibold))
                let status = WaterStatus(comment.waterStatus)
                let when = comment.createdAt.map { RelativeTime.string(since: $0) }
                let line = [status.map { "\($0.emoji) \(L10n.t($0.labelKey))" }, when].compactMap { $0 }
                if !line.isEmpty {
                    Text(line.joined(separator: " · ")).font(.footnote).foregroundStyle(.secondary)
                }
                if !comment.body.isEmpty {
                    Text(comment.body).font(.footnote).lineLimit(3)
                }
            }
            .padding(.vertical, 2)
        }
    }
}
