import CoreLocation
import Foundation
import Testing
@testable import FontApp

/// Field test, 02/10/2026: after creating a fountain, "+" opened the next one with the
/// previous one's name, choices and pin. The form kept writing its draft while it closed.
extension StubbedNetwork {
@MainActor struct NewFontDraftLifecycleTests {
    private let created = """
    {"id":"4DCBC5A0-799A-4CED-9C18-5F0BD8CB3D33","name":"Font de la plaça","latitude":41.81205,"longitude":2.09732,
    "source":"tap","createdAt":"2026-10-02T10:00:00Z","statusConflict":false,"moderationState":"visible"}
    """
    private let first = CLLocationCoordinate2D(latitude: 41.81205, longitude: 2.09732)
    /// The next fountain, a few streets away.
    private let elsewhere = CLLocationCoordinate2D(latitude: 41.81600, longitude: 2.10100)

    private func defaults() -> UserDefaults { UserDefaults(suiteName: "newfont-\(UUID().uuidString)")! }

    private func outbox() -> Outbox {
        let box = Outbox(directory: FileManager.default.temporaryDirectory.appending(path: "outbox-\(UUID().uuidString)"),
                         api: StubProtocol.client())
        box.currentUserID = UUID()
        return box
    }

    /// Fills the form as a person would, with "+" decided the way the map decides it.
    private func openAndFill(_ defaults: UserDefaults, box: Outbox) throws -> NewFontModel {
        guard case .fresh(let draft) = NewFontStart.decide(mapCenter: first, me: nil, defaults: defaults) else {
            Issue.record("the first fountain should start fresh")
            throw CancellationError()
        }
        let model = NewFontModel(draft: draft, api: StubProtocol.client(), outbox: box, defaults: defaults)
        model.followUser(from: model.pin)
        model.draft.name = "Font de la plaça"
        model.draft.source = .tap
        model.draft.drinkable = .yes
        model.draft.status = WaterStatus.flowing.rawValue
        #expect(NewFontDraft.load(defaults)?.name == "Font de la plaça", "typing keeps a draft")
        return model
    }

    /// What the sheet does while it closes: a better location fix and the small map
    /// reporting its centre both move the pin.
    private func lateChanges(_ model: NewFontModel) {
        model.userMoved(to: CLLocation(coordinate: CLLocationCoordinate2D(latitude: first.latitude + 0.00002,
                                                                          longitude: first.longitude),
                                       altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: .now))
        model.pin = CLLocationCoordinate2D(latitude: first.latitude + 0.00004, longitude: first.longitude)
        model.draft.name += " "
    }

    private func expectFreshForm(_ defaults: UserDefaults) {
        #expect(NewFontDraft.load(defaults) == nil, "nothing of the sent fountain is left on the phone")
        guard case .fresh(let next) = NewFontStart.decide(mapCenter: elsewhere, me: nil, defaults: defaults) else {
            Issue.record("the next fountain opened with the previous one's draft"); return
        }
        #expect(next.isEmpty)
        #expect(next.latitude == elsewhere.latitude && next.longitude == elsewhere.longitude,
                "the pin starts where the map is now, not where the last fountain was")
    }

    @Test func createdThenNewStartsEmptyAndHere() async throws {
        StubProtocol.responses = [
            "GET /fonts/near": (200, "[]"),
            "POST /fonts": (200, created),
            "POST /fonts/4DCBC5A0-799A-4CED-9C18-5F0BD8CB3D33/status": (200, "{}"),
        ]
        let defaults = defaults()
        let model = try openAndFill(defaults, box: outbox())
        await model.submit()
        guard case .created = model.state else { Issue.record("not created: \(model.state)"); return }
        lateChanges(model)
        expectFreshForm(defaults)
    }

    @Test func queuedWithoutSignalThenNewStartsEmptyAndHere() async throws {
        StubProtocol.responses = ["GET /fonts/near": (-1, ""), "POST /fonts": (-1, "")]
        let defaults = defaults()
        let box = outbox()
        let model = try openAndFill(defaults, box: box)
        await model.submit()
        #expect(model.state == .queued)
        #expect(box.items.first?.newFont?.name == "Font de la plaça")
        lateChanges(model)
        expectFreshForm(defaults)
    }

    @Test func discardedThenNewStartsEmptyAndHere() throws {
        let defaults = defaults()
        let model = try openAndFill(defaults, box: outbox())
        model.discard()
        lateChanges(model)
        expectFreshForm(defaults)
    }

    @Test func closedWithoutSendingIsOfferedBack() throws {
        let defaults = defaults()
        _ = try openAndFill(defaults, box: outbox())
        // Closed (Cancel → Save draft, or a swipe): the next "+" offers it, pin included.
        guard case .resume(let draft) = NewFontStart.decide(mapCenter: elsewhere, me: nil, defaults: defaults) else {
            Issue.record("a half-filled form should be offered back"); return
        }
        #expect(draft.name == "Font de la plaça")
        #expect(draft.latitude == first.latitude)
    }
}
}
