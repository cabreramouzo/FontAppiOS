import Foundation

/// A welcome is for a new installation, not for everyone updating from an older build.
/// Keep an unfinished welcome eligible after a force quit; only Skip or Explore marks it done.
enum WelcomeGate {
    static let completedKey = "welcome.native.completed.v1"

    static func shouldPresent(defaults: UserDefaults = .standard,
                              caches: URL = .cachesDirectory,
                              applicationSupport: URL = .applicationSupportDirectory,
                              hasSession: Bool = Credentials.shared.current != nil) -> Bool {
        if defaults.bool(forKey: completedKey) { return false }

        // The old app did not have a welcome marker. Recognize use of an earlier build
        // before its normal startup creates cache directories in a fresh installation.
        let oldKeys = defaults.dictionaryRepresentation().keys.contains { key in
            ["session.", "map.layer", "news.", "favorites.", "draft.", "search.recent.",
             "passing.", "guard.", "offline.", "zona."].contains { key.hasPrefix($0) }
        }
        let oldFiles = [caches.appending(path: "pins.json"),
                        applicationSupport.appending(path: "OfflineZones/zones.json"),
                        applicationSupport.appending(path: "Outbox")]
            .contains { FileManager.default.fileExists(atPath: $0.path) }
        if oldKeys || oldFiles || hasSession {
            defaults.set(true, forKey: completedKey)
            return false
        }
        return true
    }

    static func complete(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: completedKey)
    }
}
