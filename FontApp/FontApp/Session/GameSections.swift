import SwiftUI

/// Your contribution, as the web's `GamificationCard`: first the impact on the map, then
/// the drops. "12 fountains have a photo thanks to you" says something true about the
/// world; "1,240 drops" only about the counter. Nothing is drawn with the game switched
/// off, nor before you have contributed: a scoreboard at zero on day one tells you that
/// you are last.
struct GameSection: View {
    let game: GamificationSummary

    var body: some View {
        if game.gotes > 0 || game.pending > 0 {
            Section {
                if !impacts.isEmpty {
                    LazyVGrid(columns: [GridItem(.flexible(), alignment: .top), GridItem(.flexible(), alignment: .top)],
                              alignment: .leading, spacing: 12) {
                        ForEach(impacts, id: \.label) { impact in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: impact.systemImage).foregroundStyle(Color.accentColor)
                                    .frame(width: 26)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(impact.count, format: .number).font(.title2.bold())
                                    Text(impact.label).font(.caption).foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .padding(.vertical, 4)
                }
                score
                NavigationLink {
                    BadgesScreen()
                } label: {
                    Label(L10n.t("badges.title"), systemImage: "rosette")
                }
            } header: {
                Label(L10n.t("game.title"), systemImage: "drop")
            } footer: {
                if game.provisional { Text(L10n.t("game.provisional")) }
            }
        }
    }

    private var score: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(game.gotes, format: .number).font(.title3.bold())
                Text(L10n.t("game.gotes")).foregroundStyle(.secondary)
                Text(levelName(game.level))
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.15), in: Capsule())
            }
            // Already earned but not settled: without it, the card showed the old level for
            // 72 h after the congratulation.
            if let pendingLevel = game.pendingLevel {
                Text(L10n.t("game.pendingLevel", ["level": levelName(pendingLevel)]))
                    .font(.footnote.bold()).foregroundStyle(.orange)
            }
            if game.pending > 0 {
                Text(L10n.t("game.pending", ["n": game.pending]) + " · " + L10n.t("game.pendingHint"))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let next = game.nextLevel, let left = game.gotesToNextLevel, left > 0 {
                ProgressView(value: Double(game.gotes), total: Double(game.gotes + left))
                Text(L10n.t("game.toNext", ["n": left.formatted(), "level": levelName(next)]))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var impacts: [(systemImage: String, count: Int, label: String)] {
        [("camera", game.impact.fontsWithPhotoThanksToYou, L10n.t("game.impact.photos")),
         ("eye", game.impact.fontsYouKeepFresh, L10n.t("game.impact.fresh")),
         ("mappin.and.ellipse", game.impact.fontsYouPutOnTheMap, L10n.t("game.impact.created")),
         ("trophy", game.mayorCount ?? 0, L10n.t("game.impact.guardian"))]
            .filter { $0.count > 0 }
    }

    /// The server sends the key (`river`); an unknown one shows nothing rather than a key.
    private func levelName(_ key: String) -> String {
        L10n.lookup("game.level.\(key)") ?? ""
    }
}

/// The collection: how many distinct fountains you reviewed, the kinds you have, and
/// how many of the ones around you. Silent until you have visited one.
struct CollectionSection: View {
    let collection: VisitedCollection

    var body: some View {
        if collection.visited > 0 {
            Section {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(collection.visited, format: .number).font(.title2.bold())
                    Text(L10n.t("game.collection.visited")).foregroundStyle(.secondary)
                }
                if let local = collection.local, local.nearby > 0 {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.t("game.collection.localGoal", ["v": local.visited, "n": local.nearby]))
                        ProgressView(value: Double(local.visited), total: Double(local.nearby))
                        Text(L10n.t("game.collection.localRadius", ["km": local.radiusKm.formatted()]))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.t("game.collection.types", ["have": have, "total": collection.types.count]))
                        .font(.footnote).foregroundStyle(.secondary)
                    HStack(spacing: 0) {
                        ForEach(collection.types, id: \.source) { kind in
                            VStack(spacing: 2) {
                                Text(WaterSource(rawValue: kind.source)?.emoji ?? "💧").font(.title2)
                                Text(kind.count, format: .number).font(.caption.bold())
                            }
                            .frame(maxWidth: .infinity)
                            // Not yet in the collection: there, but faded.
                            .opacity(kind.count > 0 ? 1 : 0.3)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(L10n.lookup("source.\(kind.source)") ?? kind.source): \(kind.count)")
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Label(L10n.t("game.collection.title"), systemImage: "square.grid.2x2")
            }
        }
    }

    private var have: Int { collection.types.filter { $0.count > 0 }.count }
}

/// Fountains whose latest review is yours, the most forgotten first. Not tied to the game:
/// looking after a fountain is not scoring, and someone who switched points off still
/// wants to know what is going stale.
struct GuardedSection: View {
    let fonts: [GuardedFont]

    var body: some View {
        if !fonts.isEmpty {
            let stale = fonts.filter(\.stale).count
            CappedSection(title: L10n.t("guard.title"), systemImage: "shield",
                          intro: stale > 0 ? L10n.t("guard.summaryStale", ["n": fonts.count, "s": stale])
                                           : L10n.t("guard.summaryAllFresh", ["n": fonts.count]),
                          empty: "", items: fonts) { font in
                NavigationLink(value: font.fontID) {
                    HStack(spacing: 12) {
                        Text(font.source?.emoji ?? "💧").font(.title3).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.fontName(font.name)).fontWeight(font.stale ? .semibold : .regular)
                            // One text, so it wraps as a sentence and not in columns.
                            (Text(WaterStatus(font.waterStatus).map { "\($0.emoji) " } ?? "")
                             + Text(L10n.t("guard.checkedAgo", ["d": font.days]))
                             + (font.stale ? Text(" · " + L10n.t("guard.stale")).bold().foregroundStyle(.orange) : Text("")))
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .frame(minHeight: 44)
                }
            }
        }
    }
}
