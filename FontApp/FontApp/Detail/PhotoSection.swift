import CoreLocation
import PhotosUI
import SwiftUI
import UIKit

/// Shown instead of the photo when a fountain has none: take one or pick one.
struct PhotoSection: View {
    @Bindable var model: PhotoUploadModel
    let onUploaded: () async -> Void
    /// The camera is presented by the page, like every sheet opened from the list.
    let onCamera: () -> Void

    @Environment(SessionStore.self) private var session

    var body: some View {
        Section {
            Label(L10n.t("detail.noPhotoYet"), systemImage: "photo")
                .foregroundStyle(.secondary)
            if session.isSignedIn {
                content
            }
        } footer: {
            if session.isSignedIn, model.state == .idle { Text(L10n.t("detail.firstPhotoNote")) }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .uploading:
            HStack {
                ProgressView()
                Text(L10n.t("ios.uploading")).foregroundStyle(.secondary)
            }
            .frame(minHeight: 44)
        case .done:
            Text(L10n.t("toast.photoAdded"))
        case .queued:
            Label(L10n.t("offline.savedPhoto"), systemImage: "tray.and.arrow.up")
        case .idle, .failed:
            if case .failed(let message) = model.state {
                Text(message).foregroundStyle(.red)
            }
            PhotoSourceButtons(model: model, onUploaded: onUploaded, onCamera: onCamera)
        }
    }
}

/// Take a photo or choose one, for a fountain without any: under "no photo yet" and in
/// the quick review's thanks, so both behave the same.
struct PhotoSourceButtons: View {
    @Bindable var model: PhotoUploadModel
    let onUploaded: () async -> Void
    let onCamera: () -> Void

    @Environment(SessionStore.self) private var session
    @State private var pickerItem: PhotosPickerItem?

    private var cameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    var body: some View {
        HStack(spacing: 8) {
            if cameraAvailable {
                Button(action: onCamera) {
                    WideButtonLabel(L10n.t("ios.takePhoto"), systemImage: "camera")
                }
                .buttonStyle(.borderedProminent)
            }
            PhotosPicker(selection: $pickerItem, matching: .images) {
                WideButtonLabel(L10n.t("ios.choosePhoto"), systemImage: "photo.on.rectangle")
            }
            .buttonStyle(.bordered)
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                pickerItem = nil
                Task {
                    // The original file, EXIF included; a UIImage would have lost it.
                    guard let data = try? await item.loadTransferable(type: Data.self) else { return }
                    if await model.upload(original: data) { await onUploaded() }
                }
            }
        }
        .tint(session.isStaff ? Color.staff : .accentColor)
    }
}

/// The system camera. Hands back a JPEG, or `nil` when cancelled.
struct CameraPicker: UIViewControllerRepresentable {
    let onFinish: (Data?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (Data?) -> Void

        init(onFinish: @escaping (Data?) -> Void) { self.onFinish = onFinish }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let image = info[.originalImage] as? UIImage
            let jpeg = image?.jpegData(compressionQuality: 0.95)
            if let jpeg {
                // Into Photos too, so a failed send never loses it (Settings → Photos).
                // The last known position, only if location is already allowed.
                let manager = CLLocationManager()
                let allowed = [.authorizedWhenInUse, .authorizedAlways].contains(manager.authorizationStatus)
                let location = allowed ? manager.location : nil
                Task { await PhotoLibrarySaver.saveCameraShot(jpeg, at: location) }
            }
            onFinish(jpeg)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
        }
    }
}
