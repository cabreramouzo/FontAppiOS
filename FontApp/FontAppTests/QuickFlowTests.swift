import Testing
@testable import FontApp

/// After a quick review the chips' slot asks one thing at a time, in the author's order.
struct QuickFlowTests {
    @Test func photoFirstThenKindThenDrinkabilityThenName() {
        let steps = QuickFlow.steps(hasPhoto: false, missing: [.name, .drinkable, .source],
                                    remote: false, queued: false, alreadyAsked: false)
        #expect(steps == [.photo, .fact(.source), .fact(.drinkable), .fact(.name)])
    }

    @Test func noPhotoStepWhenItHasOneOrYouAreFar() {
        #expect(QuickFlow.steps(hasPhoto: true, missing: [.source], remote: false, queued: false,
                                alreadyAsked: false) == [.fact(.source)])
        #expect(QuickFlow.steps(hasPhoto: false, missing: [], remote: true, queued: false,
                                alreadyAsked: false).isEmpty)
    }

    @Test func offlineOnlyThePhotoWhichQueues() {
        #expect(QuickFlow.steps(hasPhoto: false, missing: [.source, .drinkable], remote: false, queued: true,
                                alreadyAsked: false) == [.photo])
    }

    @Test func factsAreAskedOncePerFountainAndPerson() {
        #expect(QuickFlow.steps(hasPhoto: false, missing: [.source], remote: false, queued: false,
                                alreadyAsked: true) == [.photo])
    }
}
