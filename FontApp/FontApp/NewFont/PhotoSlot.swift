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
    @State private var item: PhotosPickerItem?
    @State private var isReading = false
    @State private var unreadable = false
    @State private var unreadableReason = ""

    private static let thumbnail: CGFloat = 140

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
                Text(L10n.t("ios.photo.unreadable")).font(.footnote).foregroundStyle(.red)
                #if DEBUG
                Text(unreadableReason).font(.caption2).foregroundStyle(.secondary)
                #endif
            }
        }
        .confirmationDialog(L10n.plain("image.add"), isPresented: $asks, titleVisibility: .hidden) {
            if canTakePhoto { Button(L10n.t("ios.takePhoto"), action: onTakePhoto) }
            Button(L10n.t("ios.choosePhoto")) { showsLibrary = true }
        }
        .photosPicker(isPresented: $showsLibrary, selection: $item, matching: .images)
        .onChange(of: item) { _, chosen in
            guard let chosen else { return }
            // The selection is cleared only after it has been read: clearing it at once
            // could cut the load short, and the photo was reported unreadable.
            Task {
                await read(chosen)
                item = nil
            }
        }
    }

    private var placeholder: some View {
        Button {
            unreadable = false
            if canTakePhoto { asks = true } else { showsLibrary = true }
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

    private func read(_ chosen: PhotosPickerItem) async {
        unreadable = false
        isReading = true
        onReadingChanged(true)
        defer {
            isReading = false
            onReadingChanged(false)
        }
        // Three ways to get the original bytes, from the most to the least specific: the
        // library holds HEIC, JPEG, Live Photo stills and iCloud originals, and any one of
        // them may refuse what another gives.
        var reasons: [String] = []
        var data: Data?
        do { data = try await chosen.loadTransferable(type: PickedImage.self)?.data } catch { reasons.append("image: \(error)") }
        if data == nil {
            do { data = try await chosen.loadTransferable(type: Data.self) } catch { reasons.append("data: \(error)") }
        }
        if data == nil {
            do { data = try await chosen.loadTransferable(type: PickedFile.self)?.data } catch { reasons.append("file: \(error)") }
        }
        guard let data else { return fail("could not load the photo (\(reasons.joined(separator: "; ")))") }
        guard await onChosen(data) else { return fail("could not prepare \(data.count) bytes") }
    }

    private func fail(_ reason: String) {
        Logger(subsystem: "net.fontapp.FontApp", category: "photo").error("choosing a photo failed: \(reason, privacy: .public)")
        unreadableReason = reason
        unreadable = true
    }
}

/// A picked photo's original bytes, asked for as an image type.
private struct PickedImage: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { PickedImage(data: $0) }
    }
}

/// The same, received as a file (an iCloud original is downloaded first) and read at once.
private struct PickedFile: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            PickedFile(data: try Data(contentsOf: received.file))
        }
    }
}
