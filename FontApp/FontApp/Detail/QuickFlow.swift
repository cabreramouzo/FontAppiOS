import Foundation

/// What is asked after a quick review, one step at a time in the slot the chips leave,
/// as the web's popup replaces its own content. The order is the author's (02/10/2026):
/// the status, then the photo, then the kind of water, then drinkability, then the name.
nonisolated enum QuickFlow {
    enum Step: Hashable, Sendable {
        case photo
        case fact(MissingFact)
    }

    static let factOrder: [MissingFact] = [.source, .drinkable, .name]

    /// - Parameters:
    ///   - hasPhoto: the fountain already has a cover.
    ///   - missing: the facts it lacks, in any order.
    ///   - remote: the review was sent from far away: no photo of a fountain you are not at.
    ///   - queued: the review waits in the outbox: facts need the network, a photo queues.
    ///   - alreadyAsked: this person was asked about this fountain's facts before.
    static func steps(hasPhoto: Bool, missing: [MissingFact], remote: Bool,
                      queued: Bool, alreadyAsked: Bool) -> [Step] {
        var out: [Step] = []
        if !hasPhoto && !remote { out.append(.photo) }
        if !queued && !alreadyAsked {
            out += factOrder.filter(missing.contains).map(Step.fact)
        }
        return out
    }
}
