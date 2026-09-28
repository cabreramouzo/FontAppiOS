import SwiftUI

/// The rules of the game, public, from `GET /gamification/scale` (no session needed).
/// Port of the web's `/gamification`: every figure comes from the server, because the
/// scale has been recalibrated several times and an explanation that does not match your
/// score is worse than none. Levels, what they open, the special badges, the families,
/// then what pays and how.
nonisolated struct GamificationScale: Decodable, Sendable {
    struct Kind: Decodable, Sendable { let kind: String; let base: Int }
    struct Multiplier: Decodable, Sendable { let key: String; let factor: Double }
    struct Freshness: Decodable, Sendable { let fromDays: Int?; let gotes: Int }
    struct Level: Decodable, Sendable { let key: String; let from: Int }
    struct Family: Decodable, Sendable { let key: String; let thresholds: [Int]?; let unique: Bool? }
    struct Special: Decodable, Sendable { let key: String; let limit: Int? }
    struct Capability: Decodable, Sendable { let key: String; let level: String; let gotes: Int; let enabled: Bool? }

    var kinds: [Kind] = []
    var multipliers: [Multiplier] = []
    var maxMultiplier: Double = 1
    var desertKm: Double = 0
    var crowdedFrom: Int = 0
    var dailyCap: Int = 0
    var settleHours: Int = 0
    var freshness: [Freshness] = []
    var levels: [Level] = []
    var families: [Family] = []
    var specials: [Special] = []
    var capabilities: [Capability] = []
    var capabilitiesEnabled: Bool = false
    var capabilityActiveDays: Int = 0

    func factor(_ key: String) -> Double { multipliers.first { $0.key == key }?.factor ?? 1 }
    func base(_ kind: String) -> Int { kinds.first { $0.kind == kind }?.base ?? 0 }
}

struct GamificationGuideScreen: View {
    @State private var scale: GamificationScale?
    @State private var failed = false
    @State private var showcase: Showcase?

    var body: some View {
        List {
            Section { Text(L10n.t("gamePage.lead")).foregroundStyle(.secondary) }
            if let scale {
                content(scale)
            } else if failed {
                Text(L10n.t("badges.failed")).foregroundStyle(.secondary)
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .navigationTitle(L10n.t("gamePage.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do { scale = try await APIClient.shared.get("/gamification/scale") } catch { failed = true }
        }
        .sheet(item: $showcase) { BadgeShowcaseView(showcase: $0) }
    }

    private func n(_ v: Int) -> String { v.formatted() }
    private func x(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(0...2))) }

    private func from(_ level: GamificationScale.Level) -> String {
        level.from == 0 ? L10n.t("badges.start") : L10n.t("badges.fromGotes", ["n": n(level.from)])
    }

    @ViewBuilder private func content(_ scale: GamificationScale) -> some View {
        // The ladder, read going up.
        Section {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12)], spacing: 16) {
                ForEach(scale.levels, id: \.key) { level in
                    Button {
                        showcase = Showcase(kind: .level, key: level.key, tier: nil, locked: false, subtitle: from(level))
                    } label: {
                        VStack(spacing: 4) {
                            LevelImage(key: level.key, size: 64)
                            Text(L10n.t("game.level.\(level.key)")).font(.caption.weight(.bold)).multilineTextAlignment(.center)
                            Text(from(level)).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 6)
        } header: {
            Text(L10n.t("gamePage.levels"))
        } footer: {
            Text(L10n.t("gamePage.levelsLead"))
        }

        // What the ladder opens: without it, ten nice names with no consequence.
        if !scale.capabilities.isEmpty {
            Section {
                ForEach(scale.capabilities, id: \.key) { c in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(L10n.t("game.level.\(c.level)")) · \(L10n.t("badges.fromGotes", ["n": n(c.gotes)]))")
                            .font(.subheadline.weight(.semibold))
                        Text(L10n.t("game.can.\(c.key)") + (c.enabled == false ? " · \(L10n.t("gamePage.notYet"))" : ""))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text(L10n.t("gamePage.unlocks"))
            } footer: {
                Text([L10n.t("gamePage.unlocksAlso", ["n": n(scale.capabilityActiveDays)]),
                      scale.capabilitiesEnabled ? nil : L10n.t("gamePage.unlocksOff")]
                    .compactMap { $0 }.joined(separator: " "))
            }
        }

        if !scale.specials.isEmpty {
            Section {
                ForEach(scale.specials, id: \.key) { s in
                    badgeRow(s.key, tier: "special",
                             note: s.limit.map { L10n.t("gamePage.specialQuota", ["n": n($0)]) })
                }
            } header: {
                Text(L10n.t("badges.specials"))
            } footer: {
                Text(L10n.t("badges.specialsHint"))
            }
        }

        if !scale.families.isEmpty {
            Section {
                ForEach(scale.families, id: \.key) { f in badgeRow(f.key, tier: nil, note: tiers(f)) }
            } header: {
                Text(L10n.t("gamePage.badges"))
            } footer: {
                Text(L10n.t("gamePage.badgesLead"))
            }
        }

        // The scale, the same text as the web's (?) on the profile.
        Section(L10n.t("gameHelp.whatPays")) {
            ForEach(scale.kinds.sorted { $0.base > $1.base }, id: \.kind) { k in
                LabeledContent(L10n.t("game.kind.\(k.kind)"),
                               value: k.base == 0 ? L10n.t("gameHelp.byCurve") : n(k.base))
            }
            Text(L10n.t("gameHelp.basesNote")).font(.footnote).foregroundStyle(.secondary)
        }
        Section(L10n.t("gameHelp.multipliers")) {
            Text(L10n.t("gameHelp.mult.desert", ["f": x(scale.factor("desert")), "km": x(scale.desertKm)]))
            Text(L10n.t("gameHelp.mult.dry", ["f": x(scale.factor("dry"))]))
            Text(L10n.t("gameHelp.mult.doubt", ["f": x(scale.factor("doubt"))]))
            Text(L10n.t("gameHelp.mult.crowded", ["f": x(scale.factor("crowded")), "n": n(scale.crowdedFrom)]))
            Text(L10n.t("gameHelp.maxNote", ["m": x(scale.maxMultiplier)])).font(.footnote).foregroundStyle(.secondary)
        }
        Section(L10n.t("gameHelp.freshness")) {
            Text(L10n.t("gameHelp.freshnessNote")).font(.subheadline)
            ForEach(scale.freshness.indices, id: \.self) { i in
                let f = scale.freshness[i]
                LabeledContent(f.fromDays == nil ? L10n.t("gameHelp.freshNever")
                               : f.fromDays == 0 ? L10n.t("gameHelp.freshFirstWeek")
                               : L10n.t("gameHelp.freshFrom", ["n": n(f.fromDays!)]),
                               value: n(f.gotes))
            }
        }
        Section(L10n.t("gameHelp.example")) {
            // Built from the server's figures: an invented example is the first thing
            // that stops adding up when the scale is recalibrated.
            let base = scale.base("firstReview")
            Text(L10n.t("gameHelp.exampleText", [
                "base": n(base), "m1": x(scale.factor("desert")), "m2": x(scale.factor("dry")),
                "total": n(Int((Double(base) * scale.factor("desert") * scale.factor("dry")).rounded())),
            ]))
        }
        Section(L10n.t("gameHelp.rules")) {
            Text(L10n.t("gameHelp.settle", ["h": n(scale.settleHours)]))
            Text(L10n.t("gameHelp.cap", ["n": n(scale.dailyCap)]))
            Text(L10n.t("gameHelp.frozen"))
        }
        Section { Text(L10n.t("gamePage.optOut")).font(.footnote).foregroundStyle(.secondary) }
    }

    /// "Bronze at 10 · gold at 200", or the single tier.
    private func tiers(_ f: GamificationScale.Family) -> String {
        let t = f.thresholds ?? []
        if f.unique == true || t.isEmpty { return L10n.t("gamePage.uniqueTier") }
        return L10n.t("gamePage.tiers", ["a": n(t[0]), "b": n(t[t.count - 1])])
    }

    private func badgeRow(_ key: String, tier: String?, note: String?) -> some View {
        Button {
            showcase = Showcase(kind: .badge, key: key, tier: tier, locked: false, subtitle: note)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                BadgeImage(family: key, tier: tier, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("game.badge.\(key)")).font(.body.weight(.semibold))
                    if let about = L10n.lookup("game.badgeAbout.\(key)") {
                        Text(about).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let note { Text(note).font(.caption).foregroundStyle(.tertiary) }
                }
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }
}
