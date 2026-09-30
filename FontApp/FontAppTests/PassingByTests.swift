import CoreLocation
import Foundation
import Testing
@testable import FontApp

struct PassingByTests {
    private let here = CLLocation(latitude: 41.8, longitude: 2.1)
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func font(_ offset: Double, status: String? = nil, daysAgo: Double? = nil, conflict: Bool = false) -> FontSummary {
        FontSummary(id: UUID(), name: nil, latitude: 41.8 + offset, longitude: 2.1, image: nil, description: nil,
                    source: nil, drinkable: nil, country: nil, region: nil, createdAt: nil,
                    lastWaterStatus: status, lastUpdate: daysAgo.map { now.addingTimeInterval(-$0 * 86_400) },
                    latestConfirmations: 0, recentStatusReporters: status == nil ? 0 : 1,
                    recentStatusConflict: conflict)
    }

    @Test func asksWhereAnAnswerMattersAndSkipsWhatSomeoneJustSaid() {
        let fresh = font(0.0001, status: "flowing", daysAgo: 1)
        let never = font(0.01)
        let old = font(0.002, status: "flowing", daysAgo: 60)
        let disputed = font(0.003, status: "dry", daysAgo: 1, conflict: true)
        let chosen = PassingByRules.choose([fresh, old, never, disputed], around: here, now: now)
        // The nearest is skipped (checked yesterday); unknown and conflicting come first.
        #expect(chosen.map(\.id) == [disputed.id, never.id, old.id])
    }

    @Test func keepsToTheSlotsIOSAllows() {
        let many = (1...40).map { font(Double($0) * 0.001) }
        #expect(PassingByRules.choose(many, around: here, now: now).count == 19)
    }

    @Test func theRefreshCircleStaysWithinBounds() {
        #expect(PassingByRules.refreshRadius(for: [], around: here) == 500)
        #expect(PassingByRules.refreshRadius(for: [font(0.1)], around: here) == 3000)
    }

    @Test func fewNoticesNeverAtNightNeverTheSameFountainTwice() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
        let noon = calendar.date(from: DateComponents(year: 2026, month: 9, day: 29, hour: 12))!
        let night = calendar.date(from: DateComponents(year: 2026, month: 9, day: 29, hour: 23))!
        let id = UUID()
        #expect(PassingByRules.shouldNotify(id, history: [], now: noon, calendar: calendar))
        #expect(!PassingByRules.shouldNotify(id, history: [], now: night, calendar: calendar))
        // The same fountain within a month.
        #expect(!PassingByRules.shouldNotify(id, history: [.init(fontID: id, at: noon.addingTimeInterval(-10 * 86_400))],
                                             now: noon, calendar: calendar))
        // Another one ten minutes after the last notice.
        #expect(!PassingByRules.shouldNotify(id, history: [.init(fontID: UUID(), at: noon.addingTimeInterval(-600))],
                                             now: noon, calendar: calendar))
        // Three today already.
        let three = (1...3).map { PassingByNotice(fontID: UUID(), at: noon.addingTimeInterval(Double(-$0) * 3600)) }
        #expect(!PassingByRules.shouldNotify(id, history: three, now: noon, calendar: calendar))
    }

    @Test func aChipOnTheNoticeGoesToTheOutbox() {
        let outbox = Outbox(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
        let id = UUID()
        #expect(!PassingBy.answer(action: PassingBy.notSeenAction, userInfo: ["fontID": id.uuidString],
                                  outbox: outbox, sync: nil))
        #expect(PassingBy.answer(action: "passingBy.trickle", userInfo: ["fontID": id.uuidString, "fontName": ""],
                                 outbox: outbox, sync: nil))
        let item = outbox.items.first
        #expect(outbox.items.count == 1)
        #expect(item?.fontID == id && item?.fontName == nil)
        // Near the fountain by definition: never remote, and "still the same" if it repeats.
        #expect(item?.review == NewReview(waterStatus: "trickle", confirmIfUnchanged: true, remoteDistanceM: nil))
    }

    @Test func aVehicleOrUncertainMovementNeverPostsAPassingByNotice() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func at(_ ago: TimeInterval, car: Bool, confident: Bool = true) -> MotionSample {
            MotionSample(at: now.addingTimeInterval(-ago), automotive: car, onFoot: !car, confident: confident)
        }
        // The drive began well before the old three-minute query window; even a red
        // light with speed zero must not override the vehicle classification.
        #expect(!PassingByRules.canNotify(motion: [at(40 * 60, car: true)], speed: 0, now: now))
        #expect(!PassingByRules.canNotify(motion: [at(60, car: true)], speed: nil, now: now))
        // Core Motion can report automotive and stationary/other flags together.
        #expect(!PassingByRules.canNotify(motion: [MotionSample(at: now, automotive: true,
                                                               onFoot: true, confident: true)], speed: 0, now: now))
        // A fast fix takes priority over a lagging walking classification.
        #expect(!PassingByRules.canNotify(motion: [at(30, car: false)], speed: 8, now: now))
        // No confident recent movement evidence is not permission to send an alert.
        #expect(!PassingByRules.canNotify(motion: [at(30, car: true, confident: false)], speed: 0, now: now))
        #expect(!PassingByRules.canNotify(motion: [], speed: nil, now: now))
        #expect(!PassingByRules.canNotify(motion: [], speed: 1.4, now: now))
        #expect(!PassingByRules.canNotify(motion: [at(3 * 60 * 60, car: false)], speed: 0, now: now))
        // Parking and then walking provides a newer positive signal.
        #expect(PassingByRules.canNotify(motion: [at(150, car: true), at(30, car: false)], speed: 1.4, now: now))
        #expect(PassingByRules.canNotify(motion: [at(600, car: false)], speed: nil, now: now))
    }
}
