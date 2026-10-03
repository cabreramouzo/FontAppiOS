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

    // MARK: Photos taken with the app's camera

    /// Whether a photo taken with the app's camera is also saved into Photos. On by
    /// default: a photo lost because sending failed (no signal, the app killed, an error)
    /// cannot be taken again once you have left the fountain. Per device, in Settings.
    static let savesCameraShotsKey = "photos.saveCameraShots"

    static var savesCameraShots: Bool {
        UserDefaults.standard.object(forKey: savesCameraShotsKey) as? Bool ?? true
    }

    /// Whether iOS refused add access (the Settings toggle then says how to allow it).
    static var isDenied: Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        return status == .denied || status == .restricted
    }

    /// The camera's photo, at full quality, before it is compressed for sending, with the
    /// time and, if location is already allowed, the place. Asks for add-only access the
    /// first time; never asks for location. A failure is silent: the photo still goes on
    /// to the form as it would have.
    static func saveCameraShot(_ jpeg: Data, at location: CLLocation?) async {
        guard savesCameraShots else { return }
        _ = await save(jpeg, meta: PhotoMeta(takenAt: .now, latitude: location?.coordinate.latitude,
                                             longitude: location?.coordinate.longitude))
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
