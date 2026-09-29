import CryptoKit
import Foundation

/// The last answer to every read, kept on the phone, for when there is no signal.
///
/// With signal the app always asks the server: a fountain's status or your reviews must
/// be the current ones. Without it, a read that fails for lack of network answers with
/// what that same read returned last time — the fountain's page, your profile, the news,
/// your favourites — instead of an empty screen. On a mountain that is most of the time.
///
/// Answers that depend on the account are stored under it (a hash of the token), so
/// another account never sees them. Bounded in size; the oldest go first.
nonisolated final class ResponseCache: @unchecked Sendable {
    static let shared = ResponseCache()
    static let maxBytes = 60 * 1024 * 1024

    private let directory: URL?
    private let lock = NSLock()
    private var writesSincePrune = 0

    init(directory: URL? = URL.cachesDirectory.appending(path: "Responses", directoryHint: .isDirectory)) {
        self.directory = directory
        if let directory { try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
    }

    /// The file name for a read: its URL and, for signed-in reads, which account.
    static func key(url: URL, bearer: String?) -> String {
        let account = bearer.map { SHA256.hash(data: Data($0.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined() }
        let text = (account ?? "anon") + " " + url.absoluteString
        return SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func data(for key: String) -> Data? {
        guard let directory else { return nil }
        return try? Data(contentsOf: directory.appending(path: key))
    }

    func store(_ data: Data, for key: String) {
        guard let directory else { return }
        try? data.write(to: directory.appending(path: key), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        let prune = lock.withLock { () -> Bool in
            writesSincePrune += 1
            guard writesSincePrune >= 50 else { return false }
            writesSincePrune = 0
            return true
        }
        if prune { self.prune() }
    }

    /// Everything, on signing out: the next person on this phone starts clean.
    func clear() {
        guard let directory else { return }
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func prune() {
        guard let directory,
              let files = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]) else { return }
        let entries = files.compactMap { url -> (URL, Date, Int)? in
            guard let v = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) else { return nil }
            return (url, v.contentModificationDate ?? .distantPast, v.fileSize ?? 0)
        }.sorted { $0.1 > $1.1 }
        var total = 0
        for (url, _, size) in entries {
            total += size
            if total > Self.maxBytes { try? FileManager.default.removeItem(at: url) }
        }
    }
}
