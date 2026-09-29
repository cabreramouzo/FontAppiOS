import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// The system photo picker, as UIKit's `PHPickerViewController`, handing back the item
/// provider itself.
///
/// SwiftUI's `PhotosPicker` only lets the app ask for a `Transferable`, and on a real phone
/// that failed for every type with "no compatible representations" (a photo kept in iCloud
/// while offline, one whose original is not on the phone). The provider offers more ways to
/// get at the same picture, `LibraryPhoto.data` tries them in turn.
struct LibraryPicker: UIViewControllerRepresentable {
    let onPicked: (NSItemProvider?) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1
        // What is on the phone as it is, without converting it or waiting for a transcode.
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPicked: onPicked) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPicked: (NSItemProvider?) -> Void
        init(onPicked: @escaping (NSItemProvider?) -> Void) { self.onPicked = onPicked }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            onPicked(results.first?.itemProvider)
        }
    }
}

/// Getting the bytes of a picked photo.
enum LibraryPhoto {
    struct Failure: Error {
        /// What was tried and why each way failed, for the log.
        let detail: String
    }

    /// The original file if the phone has it; else the picture UIKit can render from what
    /// it has (which may be a smaller copy, and carries no EXIF).
    static func data(from provider: NSItemProvider) async throws -> Data {
        var reasons: [String] = ["types: \(provider.registeredTypeIdentifiers.joined(separator: ","))"]
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            do { return try await file(of: provider) } catch { reasons.append("file: \(error.localizedDescription)") }
        }
        if provider.canLoadObject(ofClass: UIImage.self) {
            do {
                if let image = try await object(of: provider), let jpeg = image.jpegData(compressionQuality: 0.95) { return jpeg }
                reasons.append("object: no image")
            } catch { reasons.append("object: \(error.localizedDescription)") }
        }
        throw Failure(detail: reasons.joined(separator: "; "))
    }

    private static func file(of provider: NSItemProvider) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, error in
                guard let url else { return continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown)) }
                // The file is deleted when this closure returns: it is read here.
                do { continuation.resume(returning: try Data(contentsOf: url)) } catch { continuation.resume(throwing: error) }
            }
        }
    }

    private static func object(of provider: NSItemProvider) async throws -> UIImage? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadObject(ofClass: UIImage.self) { object, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: object as? UIImage) }
            }
        }
    }
}
