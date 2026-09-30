import OSLog
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// The photo of a form, as the web's `ImagePicker` with `placeholder`: a big dashed zone
/// with a camera and "Add photo", instead of two bare buttons. Tapping it asks whether to
/// take the photo or choose it; once there is one, its thumbnail stays with a ✕ to remove it.
///
/// Rule R8.x in `FontAppBE/docs/client-rules.md`: a photo the person picked is always seen —
/// while it is read, as a thumbnail, or as a message saying it could not be used. Choosing
/// from the library used to leave the form as it was when the file was slow or unreadable,
/// and the person could not tell "not chosen" from "chosen and lost".
struct PhotoSlot: View {
    /// The compressed photo, if there is one.
    let jpeg: Data?
    let canTakePhoto: Bool
    let onTakePhoto: () -> Void
    /// The bytes chosen from the library. `false` when they could not be used.
    let onChosen: (Data) async -> Bool
    let onRemove: () -> Void
    var onReadingChanged: (Bool) -> Void = { _ in }

    @State private var asks = false
    @State private var showsLibrary = false
    @State private var isReading = false
    @State private var unreadable = false
    @State private var unreadableReason = ""

    private static let thumbnail: CGFloat = 140

    /// The library is offered only with signal. Without it, a photo kept in iCloud cannot be
    /// read ("no compatible representations" for every way of asking, `LibraryPhoto.data`),
    /// and a form that sometimes refuses the photo is worse than one that only takes it on
    /// the spot, which is what someone without signal is doing anyway.
    /// TODO: offer it offline too, for the photos that are on the phone (30/09/2026: some
    /// that are not fail either way). Try `PHPickerConfiguration.preferredAssetRepresentationMode
    /// = .compatible`, and `PHAsset` with limited library access, on iCloud-only photos.
    /// Without a camera (simulator, some iPads) the library is always offered: it is the only way.
    private var offersLibrary: Bool { OutboxSync.shared.isOnline }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let jpeg, let image = UIImage(data: jpeg) {
                preview(image)
            } else if isReading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(L10n.t("image.uploading")).font(.footnote).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 96)
                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            } else {
                placeholder
            }
            if unreadable {
                Text(L10n.t(OutboxSync.shared.isOnline ? "ios.photo.unreadable" : "ios.photo.icloud"))
                    .font(.footnote).foregroundStyle(.red)
                #if DEBUG
                Text(unreadableReason).font(.caption2).foregroundStyle(.secondary)
                #endif
            }
        }
        .confirmationDialog(L10n.plain("image.add"), isPresented: $asks, titleVisibility: .hidden) {
            if canTakePhoto { Button(L10n.t("ios.takePhoto"), action: onTakePhoto) }
            if offersLibrary || !canTakePhoto { Button(L10n.t("ios.choosePhoto")) { showsLibrary = true } }
        }
        .sheet(isPresented: $showsLibrary) {
            LibraryPicker { provider in
                showsLibrary = false
                guard let provider else { return }
                Task { await read(provider) }
            }
            .ignoresSafeArea()
        }
    }

    private var placeholder: some View {
        Button {
            unreadable = false
            if canTakePhoto {
                // Only the camera is offered (no signal, see `offersLibrary`): no question to ask.
                if offersLibrary { asks = true } else { onTakePhoto() }
            } else {
                showsLibrary = true
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "camera").font(.title2)
                Text(L10n.plain("image.add")).font(.subheadline.weight(.medium))
            }
            .frame(maxWidth: .infinity, minHeight: 96)
            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.accentColor.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [6, 4])))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
    }

    private func preview(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable().scaledToFill()
            .frame(width: Self.thumbnail, height: Self.thumbnail)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.secondary.opacity(0.3)))
            .accessibilityLabel(L10n.t("image.previewAlt"))
            .overlay(alignment: .topTrailing) {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(.red, in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(L10n.t("image.remove"))
                .offset(x: 12, y: -12)
            }
            .padding(.top, 12)
    }

    private func read(_ provider: NSItemProvider) async {
        unreadable = false
        isReading = true
        onReadingChanged(true)
        defer {
            isReading = false
            onReadingChanged(false)
        }
        let data: Data
        do { data = try await LibraryPhoto.data(from: provider) } catch {
            return fail("could not load the photo (\((error as? LibraryPhoto.Failure)?.detail ?? "\(error)"))")
        }
        guard await onChosen(data) else { return fail("could not prepare \(data.count) bytes") }
    }

    private func fail(_ reason: String) {
        Logger(subsystem: "net.fontapp.FontApp", category: "photo").error("choosing a photo failed: \(reason, privacy: .public)")
        unreadableReason = reason
        unreadable = true
    }
}
