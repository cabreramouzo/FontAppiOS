import CoreLocation
import Photos

/// Saves a queued photo into the Photos library (add-only access: the app cannot read it).
///
/// The queue keeps the compressed JPEG, which has no EXIF (rule R5.3), so the date and the
/// position read before compressing are put back as the asset's own.
enum PhotoLibrarySaver {
    enum Outcome: Equatable {
        case saved, denied, failed

        var messageKey: String {
            switch self {
            case .saved: "ios.photoSaved"
            case .denied: "ios.photoSaveDenied"
            case .failed: "ios.photoSaveFailed"
            }
        }
    }

    static func save(_ jpeg: Data, meta: PhotoMeta?) async -> Outcome {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return .denied }
        let takenAt = meta?.takenAt
        let position = meta?.latitude.flatMap { lat in meta?.longitude.map { CLLocation(latitude: lat, longitude: $0) } }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: jpeg, options: nil)
                request.creationDate = takenAt
                request.location = position
            }
            return .saved
        } catch {
            return .failed
        }
    }
}
