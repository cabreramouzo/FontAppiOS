import SwiftUI

/// Who you are, as the top of a profile and not a row of a list: a large avatar, the
/// name and @username, and the level with how far the next one is. Your own email is
/// not here: you know it, and it is in Settings.
struct ProfileHero: View {
    let user: UserResponse
    let staff: Bool
    let game: GamificationSummary?

    @State private var showsProvisional = false

    var body: some View {
        VStack(spacing: 8) {
            Text(initials)
                .font(.largeTitle.bold())
                .foregroundStyle(.white)
                .frame(width: 88, height: 88)
                .background(staff ? Color.staff : Color.accentColor, in: Circle())
                .accessibilityHidden(true)
            VStack(spacing: 2) {
                HStack(spacing: 6) {
                    Text(user.name).font(.title2.bold()).multilineTextAlignment(.center)
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
            }
            if let game, game.gotes > 0 || game.pending > 0 { level(game) }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    /// The level and the way to the next, as one line and a bar: the drops count, but
    /// the level is what someone remembers.
    private func level(_ game: GamificationSummary) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                if let name = L10n.lookup("game.level.\(game.level)") {
                    Text(name).font(.subheadline.bold())
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                }
                Text("\(game.gotes.formatted()) \(L10n.t("game.gotes"))").font(.subheadline).foregroundStyle(.secondary)
                if game.provisional {
                    Button { showsProvisional = true } label: {
                        Image(systemName: "info.circle").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(L10n.t("game.provisional"))
                    .popover(isPresented: $showsProvisional) {
                        Text(L10n.t("game.provisional")).font(.footnote).padding().presentationCompactAdaptation(.popover)
                    }
                }
            }
            if let next = game.nextLevel, let left = game.gotesToNextLevel, left > 0 {
                ProgressView(value: Double(game.gotes), total: Double(game.gotes + left))
                    .frame(maxWidth: 240)
                Text(L10n.t("game.toNext", ["n": left.formatted(), "level": L10n.lookup("game.level.\(next)") ?? ""]))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let pendingLevel = game.pendingLevel {
                Text(L10n.t("game.pendingLevel", ["level": L10n.lookup("game.level.\(pendingLevel)") ?? ""]))
                    .font(.caption.bold()).foregroundStyle(.orange)
            }
        }
    }

    /// First letters of the first two words, like the web's avatar.
    private var initials: String {
        let words = user.name.split(whereSeparator: \.isWhitespace).prefix(2)
        let letters = words.compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }
}

/// What you did for the map, in figures side by side: something true about the world,
/// not about a counter. Only the figures above zero.
struct ImpactStrip: View {
    let game: GamificationSummary?
    let visited: Int?

    var body: some View {
        let tiles = self.tiles
        if !tiles.isEmpty {
            HStack(alignment: .top, spacing: 0) {
                ForEach(tiles, id: \.label) { tile in
                    VStack(spacing: 4) {
                        Image(systemName: tile.systemImage).foregroundStyle(Color.accentColor)
                        Text(tile.count, format: .number).font(.title3.bold())
                        Text(tile.label).font(.caption2).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center).lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.vertical, 6)
        }
    }

    private var tiles: [(systemImage: String, count: Int, label: String)] {
        var out: [(systemImage: String, count: Int, label: String)] = []
        if let game {
            out.append(("camera", game.impact.fontsWithPhotoThanksToYou, L10n.t("game.impact.photos")))
            out.append(("eye", game.impact.fontsYouKeepFresh, L10n.t("game.impact.fresh")))
            out.append(("mappin.and.ellipse", game.impact.fontsYouPutOnTheMap, L10n.t("game.impact.created")))
        }
        if let visited { out.append(("figure.walk", visited, L10n.t("game.collection.visited"))) }
        return Array(out.filter { $0.count > 0 }.prefix(4))
    }
}

/// A row of the profile that opens a list, with how many there are.
struct ProfileLinkRow<Destination: View>: View {
    let title: String
    let systemImage: String
    var count: Int?
    var detail: String?
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink(destination: destination) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                }
            } icon: {
                Image(systemName: systemImage)
            }
            .badge(count ?? 0)
            .frame(minHeight: 44)
        }
    }
}

/// A whole list of yours on its own screen, instead of an endless profile.
struct ProfileListScreen<Item: Identifiable, Row: View>: View {
    let title: String
    var hint: String?
    let empty: String
    let items: [Item]
    @ViewBuilder let row: (Item) -> Row

    var body: some View {
        List {
            Section {
                if items.isEmpty { Text(empty).foregroundStyle(.secondary) }
                ForEach(items) { row($0) }
            } footer: {
                if let hint { Text(hint) }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A list that shows its first six and a "see them all (N)" that opens the rest, as the
/// web's `ListaConTope`. Nothing yet reads the empty text; still loading, a spinner.
struct CappedSection<Item: Identifiable, Row: View>: View {
    let title: String
    let systemImage: String
    /// Read before the list: what matters is often a count, not the rows.
    var intro: String?
    var hint: String?
    let empty: String
    let items: [Item]?
    @ViewBuilder let row: (Item) -> Row

    static var cap: Int { 6 }
    @State private var showsAll = false

    var body: some View {
        Section {
            if let intro {
                Text(intro).font(.footnote).foregroundStyle(.secondary)
            }
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
///
/// The profile's lists are pushed with destination links, so their rows are too. A value
/// link (`NavigationLink(value:)`) adds to the stack's path, which is drawn *under* the
/// screens pushed by destination: the fountain opened behind the list, nothing seemed
/// to happen, and every tap stacked another one (field test, 03/10/2026).
struct ProfileFontRow: View {
    let font: FontSummary

    var body: some View {
        NavigationLink { FontDetailView(fontID: font.id) } label: {
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
        NavigationLink { FontDetailView(fontID: comment.fontID) } label: {
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
