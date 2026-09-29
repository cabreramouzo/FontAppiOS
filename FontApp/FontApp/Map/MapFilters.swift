import Foundation

/// What the map hides. Port of the web's map filters (`MapPage.tsx`).
///
/// Everything shows by default, non-potable fountains included: hiding a fountain the
/// moment someone marks it non-potable made people think it was gone and add it again,
/// which is the worst kind of duplicate.
///
/// Kept for this run of the app only, as the web keeps them per session: coming back
/// tomorrow to a map with fountains missing, without remembering a switch, is worse.
nonisolated struct MapFilters: Equatable, Sendable {
    var onlyWithWater = false
    var onlyReliable = false
    var hideNonPotable = false
    var source: WaterSource?

    var activeCount: Int {
        [onlyWithWater, onlyReliable, hideNonPotable, source != nil].filter { $0 }.count
    }

    /// `keep`: fountains shown whatever the filters say (one just created is always
    /// unconfirmed, so "only confirmed" would hide it in front of its author).
    func apply(_ fonts: [FontSummary], now: Date = .now, keep: (UUID) -> Bool = { _ in false }) -> [FontSummary] {
        guard activeCount > 0 else { return fonts }
        return fonts.filter { font in
            if keep(font.id) { return true }
            if hideNonPotable, font.drinkable == .no { return false }
            if onlyWithWater, font.lastWaterStatus != "flowing", font.lastWaterStatus != "trickle" { return false }
            if onlyReliable, Confidence.level(of: font.evidence, now: now) != .verified { return false }
            if let source, font.source != source { return false }
            return true
        }
    }
}
