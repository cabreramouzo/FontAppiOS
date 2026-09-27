import CoreLocation
import Foundation
import Observation

/// The first photo of a fountain that has none: anyone signed in may add it. Replacing an
/// existing one is for its creator or an admin, so the app only offers the empty case.
@Observable
final class PhotoUploadModel {
    enum State: Equatable {
        case idle
        case uploading
        case done
        /// No signal: saved in the outbox, uploaded when there is signal.
        case queued
        case failed(String)
    }

    let fontID: UUID
    let fontName: String?
    private(set) var state: State = .idle

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let outbox: Outbox

    init(fontID: UUID, fontName: String? = nil, api: APIClient = .shared, outbox: Outbox = .shared) {
        self.fontID = fontID
        self.fontName = fontName
        self.api = api
        self.outbox = outbox
    }

    /// A photo from the library: its own EXIF says when and where it was taken.
    func upload(original: Data) async -> Bool {
        state = .uploading
        do {
            let prepared = try await Task.detached(priority: .userInitiated) {
                try PhotoPreparer.prepare(original)
            }.value
            return await send(prepared.jpeg, meta: prepared.meta)
        } catch let error as APIError {
            state = .failed(ErrorText.describe(error))
        } catch {
            state = .failed(L10n.t("photo.failed"))
        }
        return false
    }

    /// A photo just taken with the camera. The camera hands over pixels without EXIF, but
    /// the facts are known: it was taken now, and here if the position is fresh.
    func upload(cameraJPEG: Data, fix: CLLocation?) async -> Bool {
        state = .uploading
        var meta = PhotoMeta(takenAt: .now)
        if let fix, fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= RemoteReview.maxAccuracy,
           Date.now.timeIntervalSince(fix.timestamp) <= RemoteReview.maxFixAge {
            meta.latitude = fix.coordinate.latitude
            meta.longitude = fix.coordinate.longitude
        }
        do {
            let prepared = try await Task.detached(priority: .userInitiated) {
                try PhotoPreparer.prepare(cameraJPEG)
            }.value
            return await send(prepared.jpeg, meta: meta)
        } catch {
            state = .failed(L10n.t("photo.failed"))
            return false
        }
    }

    private func send(_ jpeg: Data, meta: PhotoMeta) async -> Bool {
        do {
            let url = try await api.uploadImage(jpeg, meta: meta)
            try await api.setFontPhoto(fontID, image: url)
            state = .done
            NotificationCenter.default.post(name: .fontChanged, object: fontID)
            return true
        } catch let error as APIError where error.status == 0 {
            // In front of a fountain without a photo is exactly where signal is worst.
            // The JPEG is already compressed and its EXIF read, so the queue keeps both.
            do {
                try outbox.enqueuePhoto(jpeg: jpeg, meta: meta, fontID: fontID, fontName: fontName)
                state = .queued
            } catch {
                state = .failed(ErrorText.describe(error))
            }
            return false
        } catch {
            // A 429 on uploads (30 an hour) carries Retry-After; ErrorText says how long.
            state = .failed(ErrorText.describe(error))
            return false
        }
    }
}
