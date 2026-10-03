import SwiftUI

/// The collection: how many distinct fountains you reviewed, the kinds you have, and
/// how many of the ones around you. Silent until you have visited one.
struct CollectionSection: View {
    let collection: VisitedCollection
    /// A medal you have was tapped: its kind's list opens. Buttons, not one NavigationLink
    /// per medal: six links in one list row all fire on a tap, pushing every kind's list,
    /// and Back then walked through each of them (field test, 03/10/2026).
    let onOpen: (WaterSource) -> Void

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
                            let medal = VStack(spacing: 2) {
                                Text(WaterSource(rawValue: kind.source)?.emoji ?? "💧").font(.title2)
                                Text(kind.count, format: .number).font(.caption.bold())
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                            // Not yet in the collection: there, but faded.
                            .opacity(kind.count > 0 ? 1 : 0.3)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(L10n.lookup("source.\(kind.source)") ?? kind.source): \(kind.count)")
                            // You see the number and want to know which ones: a kind you have
                            // opens its list. One you lack has nothing to show.
                            if kind.count > 0, let source = WaterSource(rawValue: kind.source) {
                                // Borderless: a row's own tap would otherwise take the whole row.
                                Button { onOpen(source) } label: { medal }
                                    .buttonStyle(.borderless)
                                    .tint(.primary)
                            } else {
                                medal
                            }
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
                NavigationLink { FontDetailView(fontID: font.fontID) } label: {
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

/// Your visited fountains of one kind, opened from its medal in the collection.
struct CollectionKindScreen: View {
    let source: WaterSource
    @State private var fonts: [CollectionFont]?
    @State private var error: String?

    var body: some View {
        List {
            if let error {
                Text(error).foregroundStyle(.secondary)
            } else if let fonts {
                ForEach(fonts) { font in
                    NavigationLink { FontDetailView(fontID: font.id) } label: {
                        HStack(spacing: 12) {
                            Text(source.emoji).font(.title3).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.fontName(font.name))
                                if let place = font.municipality ?? font.region {
                                    Text(place).font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .frame(minHeight: 44)
                    }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("\(source.emoji) \(L10n.t("source.\(source.rawValue)"))")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do { fonts = try await APIClient.shared.collectionFonts(source: source) }
            catch { self.error = ErrorText.describe(error) }
        }
    }
}

/// Your collection: the fountains you visited and their kinds, then the badges and
/// levels. One place for both, where the profile used to have two «collections».
struct CollectionScreen: View {
    let collection: VisitedCollection?
    @State private var openKind: WaterSource?

    var body: some View {
        List {
            if let collection { CollectionSection(collection: collection) { openKind = $0 } }
            Section {
                NavigationLink { BadgesScreen() } label: {
                    Label(L10n.t("gamePage.badges"), systemImage: "rosette").frame(minHeight: 44)
                }
            }
        }
        .navigationTitle(L10n.t("badges.title"))
        .navigationBarTitleDisplayMode(.inline)
        // On the list, not inside it: a destination in a lazy section is ignored.
        .navigationDestination(item: $openKind) { CollectionKindScreen(source: $0) }
    }
}
