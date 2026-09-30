import Foundation
import Testing
@testable import FontApp

struct WelcomeGateTests {
    @Test func newInstallationShowsUntilCompleted() {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }

        #expect(WelcomeGate.shouldPresent(defaults: defaults, caches: root, applicationSupport: root, hasSession: false))
        WelcomeGate.complete(defaults: defaults)
        #expect(!WelcomeGate.shouldPresent(defaults: defaults, caches: root, applicationSupport: root, hasSession: false))
    }

    @Test func anOlderInstallationSkipsTheNewWelcome() {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("world", forKey: "map.layer")

        #expect(!WelcomeGate.shouldPresent(defaults: defaults, hasSession: false))
        #expect(defaults.bool(forKey: WelcomeGate.completedKey))
    }
}
