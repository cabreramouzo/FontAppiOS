import Foundation
import Observation
import OSLog

/// A contribution made without signal, waiting on this phone to be sent.
nonisolated struct OutboxItem: Codable, Identifiable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        /// A quick review (status only) of a fountain that exists.
        case review
        /// The first photo of a fountain that has none.
        case photo
        /// A new fountain, with its photo and first status if it had them. The status goes
        /// with it, not as its own item: a review of a fountain that does not exist yet
        /// could not be sent.
        case font
        /// A full review from the page (status, stars, text, photo), as the web queues it.
        case comment
    }

    let id: UUID
    let kind: Kind
    let fontID: UUID
    /// Only so the pending list reads "Font del Faig" and not a UUID. Never sent.
    let fontName: String?
    /// Who queued it. Sent only under that account: a review saved with one account must
    /// never be published signed by whoever is signed in when the signal comes back.
    let userID: UUID?
    let queuedAt: Date
    var attempts: Int
    /// The session expired while sending: it waits for a new sign-in.
    var needsAuth: Bool
    /// For `review`. The remote distance was measured when it was written, so a review
    /// sent from home the next day is not mistaken for a remote one.
    let review: NewReview?
    /// For `photo`: the already-compressed JPEG, a file next to the index, and the EXIF
    /// read before compressing (it cannot be read again from the stored file).
    let photoFile: String?
    let photoMeta: PhotoMeta?
    /// For `font`.
    var newFont: NewFont? = nil
    var firstStatus: String? = nil
    /// For `comment`; its photo, if any, is `photoFile`.
    var comment: ComposedReview? = nil
}

/// The outbox: contributions saved on the phone and sent when there is signal.
///
/// Same rules as `web/src/lib/outbox.ts`: anything transient (no network, 429, 5xx) is
/// retried for ever, because a contribution is never lost for something that does not
/// depend on it; a 401 waits for the person to sign in again; any other 4xx (the
/// fountain was deleted, someone put a photo in the meantime…) is dropped after three
/// attempts so it does not block the queue for ever. Items go out in the order they were
/// saved, and a flush stops at the first transient failure.
@Observable
final class Outbox {
    static let shared = Outbox()
    static let maxAttempts = 3

    private(set) var items: [OutboxItem] = []
    private(set) var isFlushing = false
    /// Items sent by the last flush; the UI can say "sent".
    private(set) var lastSent = 0
    /// A flush already ran since something was last queued: the notice then says "it will
    /// be retried" instead of "it will be sent".
    private(set) var flushTried = false

    /// The account signed in now. Set by the app from `SessionStore`.
    var currentUserID: UUID?

    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let log = Logger(subsystem: "net.fontapp.FontApp", category: "outbox")

    init(directory: URL? = nil, api: APIClient = .shared) {
        let base = directory ?? URL.applicationSupportDirectory.appending(path: "Outbox", directoryHint: .isDirectory)
        self.directory = base
        self.api = api
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        items = Self.load(from: Self.indexURL(in: base))
    }

    /// Mine to send now: queued by this account (or by an older build that did not record
    /// it) and not waiting for a sign-in.
    func isMine(_ item: OutboxItem) -> Bool {
        item.userID == nil || item.userID == currentUserID
    }

    var mine: [OutboxItem] { items.filter(isMine) }
    /// Saved by another account than the one signed in. Signed out, nothing is someone
    /// else's: it all waits for a sign-in.
    var othersCount: Int { currentUserID == nil ? 0 : items.count - mine.count }

    /// For the list: marked "another account" only when someone else is signed in.
    func isOthers(_ item: OutboxItem) -> Bool { currentUserID != nil && !isMine(item) }
    var needsAuth: Bool { items.contains { $0.needsAuth && isMine($0) } }

    // MARK: Queueing

    @discardableResult
    func enqueueReview(_ review: NewReview, fontID: UUID, fontName: String?) -> OutboxItem {
        append(OutboxItem(id: UUID(), kind: .review, fontID: fontID, fontName: fontName, userID: currentUserID,
                          queuedAt: .now, attempts: 0, needsAuth: false, review: review,
                          photoFile: nil, photoMeta: nil))
    }

    @discardableResult
    func enqueuePhoto(jpeg: Data, meta: PhotoMeta, fontID: UUID, fontName: String?) throws -> OutboxItem {
        let id = UUID()
        let file = "\(id.uuidString).jpg"
        try jpeg.write(to: directory.appending(path: file), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return append(OutboxItem(id: id, kind: .photo, fontID: fontID, fontName: fontName, userID: currentUserID,
                                 queuedAt: .now, attempts: 0, needsAuth: false, review: nil,
                                 photoFile: file, photoMeta: meta))
    }

    @discardableResult
    func enqueueFont(_ font: NewFont, firstStatus: String?, jpeg: Data?, meta: PhotoMeta?) throws -> OutboxItem {
        let id = UUID()
        var file: String?
        if let jpeg {
            file = "\(id.uuidString).jpg"
            try jpeg.write(to: directory.appending(path: file!), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        return append(OutboxItem(id: id, kind: .font, fontID: id, fontName: font.name, userID: currentUserID,
                                 queuedAt: .now, attempts: 0, needsAuth: false, review: nil,
                                 photoFile: file, photoMeta: meta, newFont: font, firstStatus: firstStatus))
    }

    @discardableResult
    func enqueueComment(_ comment: ComposedReview, jpeg: Data?, meta: PhotoMeta?, fontID: UUID,
                        fontName: String?) throws -> OutboxItem {
        let id = UUID()
        var file: String?
        if let jpeg {
            file = "\(id.uuidString).jpg"
            try jpeg.write(to: directory.appending(path: file!), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        return append(OutboxItem(id: id, kind: .comment, fontID: fontID, fontName: fontName, userID: currentUserID,
                                 queuedAt: .now, attempts: 0, needsAuth: false, review: nil,
                                 photoFile: file, photoMeta: meta, comment: comment))
    }

    private func append(_ item: OutboxItem) -> OutboxItem {
        items.append(item)
        flushTried = false
        save()
        log.info("queued \(item.kind.rawValue, privacy: .public), \(self.items.count) pending")
        return item
    }

    /// Removes an item without sending it: an undo, or a discard the person confirmed.
    func remove(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        items.removeAll { $0.id == id }
        if let file = item.photoFile { try? FileManager.default.removeItem(at: directory.appending(path: file)) }
        save()
    }

    /// Destructive: these exist only on this phone. The caller asks first.
    func discard(onlyOthers: Bool = false) {
        for item in items where !onlyOthers || !isMine(item) { remove(item.id) }
    }

    /// After deleting an account: what it left here can never be sent under it again.
    func discard(queuedBy userID: UUID) {
        for item in items where item.userID == userID { remove(item.id) }
    }

    func photoData(of item: OutboxItem) -> Data? {
        item.photoFile.flatMap { try? Data(contentsOf: directory.appending(path: $0)) }
    }

    // MARK: Sending

    /// A new session: what was waiting for a sign-in can go.
    func sessionChanged(to userID: UUID?) {
        currentUserID = userID
        guard userID != nil else { return }
        var changed = false
        for i in items.indices where items[i].needsAuth {
            items[i].needsAuth = false
            changed = true
        }
        if changed { save() }
    }

    /// Sends what is pending, oldest first. Returns how many went out.
    @discardableResult
    func flush() async -> Int {
        guard !isFlushing, currentUserID != nil else { return 0 }
        isFlushing = true
        defer { isFlushing = false }
        var sent = 0
        for item in items where isMine(item) && !item.needsAuth {
            do {
                try await send(item)
                remove(item.id)
                sent += 1
                NotificationCenter.default.post(name: .fontChanged, object: item.fontID)
            } catch let error as APIError where error.status == 401 {
                update(item.id) { $0.needsAuth = true }
                break
            } catch let error as APIError where error.status == 0 || error.status == 429 || error.status >= 500 {
                log.info("flush stopped: \(error.status) (transient)")
                break
            } catch {
                // Only a 4xx says these data will never go in: a few tries and out.
                let attempts = item.attempts + 1
                if attempts >= Self.maxAttempts {
                    log.error("dropping \(item.kind.rawValue, privacy: .public) after \(attempts) attempts")
                    remove(item.id)
                } else {
                    update(item.id) { $0.attempts = attempts }
                }
            }
        }
        lastSent = sent
        flushTried = true
        return sent
    }

    private func send(_ item: OutboxItem) async throws {
        switch item.kind {
        case .review:
            guard let review = item.review else { return }
            _ = try await api.postReview(on: item.fontID, review, queuedOffline: true)
        case .photo:
            guard let jpeg = photoData(of: item) else { return }
            let url = try await api.uploadImage(jpeg, meta: item.photoMeta ?? PhotoMeta())
            // If someone put a photo meanwhile, the server says 403: dropped after a few
            // tries, which is right — replacing is not for anyone.
            try await api.setFontPhoto(item.fontID, image: url, queuedOffline: true)
        case .comment:
            guard var comment = item.comment else { return }
            if let jpeg = photoData(of: item) {
                comment.image = try await api.uploadImage(jpeg, meta: item.photoMeta ?? PhotoMeta())
            }
            _ = try await api.postComment(on: item.fontID, comment, queuedOffline: true)
        case .font:
            guard var font = item.newFont else { return }
            if let jpeg = photoData(of: item) {
                font.image = try await api.uploadImage(jpeg, meta: item.photoMeta ?? PhotoMeta())
            }
            let created = try await api.createFont(font, queuedOffline: true)
            // Best effort: the fountain exists now, and must not be queued again for this.
            if let status = item.firstStatus {
                try? await api.postStatus(on: created.id, status, queuedOffline: true)
            }
        }
    }

    private func update(_ id: UUID, _ change: (inout OutboxItem) -> Void) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[i])
        save()
    }

    // MARK: Storage

    private static func indexURL(in directory: URL) -> URL { directory.appending(path: "items.json") }

    private static func load(from url: URL) -> [OutboxItem] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([OutboxItem].self, from: data)) ?? []
    }

    /// Readable after the first unlock, so the background task can send it.
    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: Self.indexURL(in: directory),
                        options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
