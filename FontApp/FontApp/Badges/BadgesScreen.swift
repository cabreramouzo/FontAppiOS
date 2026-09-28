import SwiftUI

/// The showcase, as the web's `/me/badges`: the ladder of levels, the specials and the
/// families with their progress. Every one opens large, earned or not: seeing where you
/// are going is half the point of the ladder.
struct BadgesScreen: View {
    @State private var game: GamificationSummary?
    @State private var state: LoadState = .loading
    @State private var showing: Showcase?

    enum LoadState { case loading, loaded, off, failed }

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 12, alignment: .top)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(L10n.t("badges.intro")).font(.subheadline).foregroundStyle(.secondary)
                switch state {
                case .loading: ProgressView().frame(maxWidth: .infinity)
                case .failed: Text(L10n.t("badges.failed")).foregroundStyle(.secondary)
                case .off: Text(L10n.t("badges.hidden")).foregroundStyle(.secondary)
                case .loaded:
                    if let game { content(game) }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(L10n.t("badges.title"))
        .task { await load() }
        .sheet(item: $showing) { BadgeShowcaseView(showcase: $0) }
    }

    private func load() async {
        do {
            if let summary = try await APIClient.shared.gamification() {
                game = summary
                state = .loaded
            } else {
                state = .off
            }
        } catch {
            state = .failed
        }
    }

    @ViewBuilder private func content(_ game: GamificationSummary) -> some View {
        if let levels = game.levels, !levels.isEmpty {
            section(L10n.t("badges.levels"), hint: L10n.t("badges.levelsHint")) {
                ForEach(levels) { level in
                    let detail = level.from == 0 ? L10n.t("badges.start") : L10n.t("badges.fromGotes", ["n": level.from.formatted()])
                    cell(name: L10n.t("game.level.\(level.key)"), detail: detail, dimmed: !level.reached,
                         tag: level.current ? L10n.t("badges.current") : nil, tagColor: .accentColor) {
                        LevelImage(key: level.key, locked: !level.reached)
                    } open: {
                        Showcase(kind: .level, key: level.key, tier: nil, locked: !level.reached, subtitle: detail)
                    }
                }
            }
        }
        if let special = game.special, !special.isEmpty {
            section(L10n.t("badges.specials"), hint: L10n.t("badges.specialsHint")) {
                ForEach(special) { badge in
                    let earned = badge.earnedAt != nil
                    let detail = specialDetail(badge)
                    cell(name: L10n.t("game.badge.\(badge.key)"), detail: detail, dimmed: !earned,
                         tag: earned ? L10n.t("badges.specialTier") : nil, tagColor: .purple) {
                        BadgeImage(family: badge.key, tier: "special", locked: !earned)
                    } open: {
                        Showcase(kind: .badge, key: badge.key, tier: nil, locked: !earned, subtitle: detail)
                    }
                }
            }
        }
        if let collection = game.collection, !collection.isEmpty {
            section(L10n.t("badges.families"), hint: L10n.t("badges.familiesHint")) {
                ForEach(collection) { slot in
                    // Earned counting what still settles: in colour and without a lock, or
                    // the badge looks taken away right after the confetti.
                    let onTheWay = slot.tier == nil && slot.pendingTier != nil
                    let locked = slot.tier == nil && !onTheWay
                    let progress = slot.maxed ? L10n.t("badges.maxed")
                        : L10n.t("badges.progress", ["n": slot.progress, "m": slot.threshold])
                    cell(name: L10n.t("game.badge.\(slot.family)"),
                         detail: onTheWay ? L10n.t("badges.settlingHint") : progress, dimmed: locked,
                         tag: slot.tier.map { L10n.t("game.tier.\($0)") } ?? (onTheWay ? L10n.t("badges.onTheWay") : nil),
                         tagColor: TierColor.color(slot.tier) ?? (onTheWay ? .orange : .accentColor),
                         progress: slot.maxed ? nil : Double(slot.progress) / Double(max(slot.threshold, 1))) {
                        BadgeImage(family: slot.family, tier: slot.tier ?? slot.pendingTier, locked: locked)
                    } open: {
                        Showcase(kind: .badge, key: slot.family, tier: slot.tier ?? slot.pendingTier, locked: locked,
                                 subtitle: progress)
                    }
                }
            }
        }
    }

    private func specialDetail(_ badge: SpecialStanding) -> String {
        let places = badge.remaining.map { $0 == 0 ? L10n.t("badges.specialGone") : L10n.t("badges.specialLeft", ["n": $0.formatted()]) }
        if let earned = badge.earnedAt {
            let date = L10n.t("badges.specialEarnedOn", ["d": earned.formatted(date: .long, time: .omitted)])
            return [date, places].compactMap { $0 }.joined(separator: " · ")
        }
        return places ?? L10n.t("game.badgeAbout.\(badge.key)")
    }

    private func section(_ title: String, hint: String, @ViewBuilder cells: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.title3.bold())
            Text(hint).font(.footnote).foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 16) { cells() }
                .padding(.top, 4)
        }
    }

    private func cell(name: String, detail: String, dimmed: Bool, tag: String?, tagColor: Color,
                      progress: Double? = nil, @ViewBuilder image: () -> some View,
                      open: @escaping () -> Showcase) -> some View {
        Button {
            showing = open()
        } label: {
            VStack(spacing: 6) {
                image()
                Text(name).font(.footnote.bold()).multilineTextAlignment(.center)
                    .foregroundStyle(dimmed ? .secondary : .primary)
                if let tag {
                    Text(tag).font(.caption2.bold()).foregroundStyle(tagColor)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .overlay(Capsule().strokeBorder(tagColor))
                }
                Text(detail).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if let progress {
                    ProgressView(value: min(max(progress, 0), 1)).tint(tagColor)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(10)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

/// A level or a badge, large.
struct Showcase: Identifiable {
    enum Kind { case level, badge }
    let kind: Kind
    let key: String
    let tier: String?
    let locked: Bool
    let subtitle: String?
    var id: String { "\(kind)-\(key)" }
}

struct BadgeShowcaseView: View {
    let showcase: Showcase
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    art
                        .scaleEffect(appeared || reduceMotion ? 1 : 0.5)
                        .rotationEffect(.degrees(appeared || reduceMotion ? 0 : -12))
                        .opacity(appeared ? 1 : 0)
                        .padding(.top, 24)
                    Text(name).font(.title2.bold()).multilineTextAlignment(.center)
                    if let tier = showcase.tier, !showcase.locked, tier != "unique" {
                        Text(L10n.t("game.tier.\(tier)")).font(.subheadline.bold())
                            .foregroundStyle(TierColor.color(tier) ?? .secondary)
                    }
                    if let subtitle = showcase.subtitle {
                        Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let about {
                        Text(about).multilineTextAlignment(.center).padding(.top, 4)
                    }
                }
                .padding()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button(role: .close) { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) { appeared = true } }
    }

    @ViewBuilder private var art: some View {
        switch showcase.kind {
        case .level: LevelImage(key: showcase.key, locked: showcase.locked, size: 200)
        case .badge: BadgeImage(family: showcase.key, tier: showcase.tier, locked: showcase.locked, size: 200)
        }
    }

    private var name: String {
        L10n.t(showcase.kind == .level ? "game.level.\(showcase.key)" : "game.badge.\(showcase.key)")
    }

    private var about: String? {
        L10n.lookup(showcase.kind == .level ? "game.levelAbout" : "game.badgeAbout.\(showcase.key)")
    }
}
