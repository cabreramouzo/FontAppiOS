import CoreLocation
import SwiftUI

/// One photo of a fountain: the cover, or one a review brought.
/// Port of `web/src/lib/fountainPhotos.ts`.
nonisolated struct FountainPhoto: Identifiable, Sendable {
    let id: String
    let image: String
    let review: CommentResponse?

    /// The cover first, then the reviews' photos, newest first.
    static func all(cover: String?, reviews: [CommentResponse]) -> [FountainPhoto] {
        var photos = cover.map { [FountainPhoto(id: "cover", image: $0, review: nil)] } ?? []
        let sorted = reviews.sorted {
            $0.createdAt != $1.createdAt ? $0.createdAt > $1.createdAt : $0.id.uuidString < $1.id.uuidString
        }
        for review in sorted {
            if let image = review.image { photos.append(FountainPhoto(id: review.id.uuidString, image: image, review: review)) }
        }
        return photos
    }

    /// The newest review's photo, when that review is under 30 days old. A newer review
    /// without a photo must not make an older photo look current; confirmations refresh
    /// the report, never the photograph's age.
    static func latestReviewPhoto(_ reviews: [CommentResponse], now: Date = .now) -> String? {
        let latest = reviews.max {
            $0.createdAt != $1.createdAt ? $0.createdAt < $1.createdAt : $0.id.uuidString > $1.id.uuidString
        }
        guard let latest, latest.image != nil else { return nil }
        let age = now.timeIntervalSince(latest.createdAt)
        return age >= 0 && age <= 30 * 86_400 ? latest.id.uuidString : nil
    }
}

/// Every photo of the fountain, one swipe apart, as the web's carousel. A tap opens them
/// full screen, where they can be zoomed.
struct PhotoCarousel: View {
    let name: String
    let photos: [FountainPhoto]
    let url: (String) -> URL?
    /// The newest review's photo, offered with a button when another one is showing.
    var latestID: String? = nil
    /// Whether this review's photo may become the cover (the page decides who can).
    var canPromote: (CommentResponse) -> Bool = { _ in false }
    var onPromote: (CommentResponse) -> Void = { _ in }
    /// Admins see what the camera wrote, to judge a doubtful photo; never to act alone.
    var exifFor: CLLocationCoordinate2D? = nil

    @State private var index = 0
    @State private var viewing: Int?
    @State private var meta: [String: PhotoExif] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TabView(selection: $index) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { i, photo in
                    Button { viewing = i } label: { FilledPhoto(url: url(photo.image)) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(name) — \(L10n.t(photo.review == nil ? "carousel.cover" : "carousel.review"))")
                        .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .always : .never))
            .aspectRatio(4 / 3, contentMode: .fit)
            .accessibilityLabel(L10n.t("carousel.label"))
            caption.padding(.horizontal, 16).padding(.bottom, 8)
        }
        // After a new cover, the list changes under the index: back to the cover.
        .onChange(of: photos.map(\.id)) { index = 0 }
        .task(id: exifFor == nil ? [] : photos.map(\.image)) {
            guard exifFor != nil else { return }
            let ids = photos.compactMap { PhotoExif.id(of: $0.image) }
            guard !ids.isEmpty, let rows = try? await APIClient.shared.photoExif(ids) else { return }
            meta = Dictionary(rows.map { ($0.photoID.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })
        }
        .fullScreenCover(item: Binding(get: { viewing.map(Viewing.init) }, set: { viewing = $0?.index })) { v in
            PhotoViewer(name: name, photos: photos, url: url, index: v.index)
        }
    }

    private struct Viewing: Identifiable { let index: Int; var id: Int { index } }

    @ViewBuilder private var caption: some View {
        let photo = photos[min(index, photos.count - 1)]
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(L10n.t(photo.review == nil ? "carousel.cover" : "carousel.review"))
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .overlay(Capsule().strokeBorder(.secondary.opacity(0.5)))
                if let review = photo.review {
                    Text(review.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if photos.count > 1 {
                    Text("\(index + 1) / \(photos.count)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            // The line is kept even for the cover, so swiping to a review does not push
            // what is below it.
            HStack(spacing: 8) {
                if let review = photo.review {
                    if let user = review.username { Text("@\(user)").font(.footnote) }
                    if let status = WaterStatus(review.waterStatus) {
                        Text("\(L10n.t("carousel.reportedStatus")): \(status.emoji) \(L10n.t(status.labelKey))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(minHeight: 20)
            HStack(spacing: 16) {
                if let latestID, latestID != photo.id, let i = photos.firstIndex(where: { $0.id == latestID }) {
                    Button(L10n.t("carousel.latest")) { withAnimation { index = i } }
                }
                if let review = photo.review, canPromote(review) {
                    Button(L10n.t("detail.useAsMainPhoto")) { onPromote(review) }
                }
            }
            .buttonStyle(.borderless)
            .font(.subheadline)
            if let fountain = exifFor, let id = PhotoExif.id(of: photo.image), let m = meta[id] {
                Label(exifLine(m, fountain: fountain), systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityHint(L10n.t("exif.hint"))
            }
        }
    }

    /// When, how long before upload, and how far from the fountain: a distance says more
    /// than two numbers, and is less personal data on screen. Missing is normal
    /// (messaging apps strip it), so it is said plainly.
    private func exifLine(_ m: PhotoExif, fountain: CLLocationCoordinate2D) -> String {
        var parts: [String] = []
        if let taken = m.takenAt {
            parts.append(L10n.t("exif.taken", ["d": taken.formatted(date: .numeric, time: .shortened)]))
            if let up = m.uploadedAt {
                let days = Int(up.timeIntervalSince(taken) / 86_400)
                parts.append(days < 1 ? L10n.t("exif.sameDay") : L10n.t("exif.daysBefore", ["n": days]))
            }
        } else {
            parts.append(L10n.t("exif.noDate"))
        }
        if let lat = m.latitude, let long = m.longitude {
            let d = CLLocation(latitude: lat, longitude: long)
                .distance(from: CLLocation(latitude: fountain.latitude, longitude: fountain.longitude))
            let text = d < 1000 ? "\(Int(d.rounded())) m"
                : Measurement(value: d / 1000, unit: UnitLength.kilometers)
                    .formatted(.measurement(width: .abbreviated, numberFormatStyle: .number.precision(.fractionLength(1))))
            parts.append(L10n.t("exif.near", ["d": text]))
        } else {
            parts.append(L10n.t("exif.noGps"))
        }
        return parts.joined(separator: " · ")
    }
}

/// A photo whole, on the same photo blurred: portrait photos in a landscape frame keep
/// the spout instead of being cropped, and the bands are not empty (as the web does).
private struct FilledPhoto: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                ZStack {
                    image.resizable().scaledToFill().blur(radius: 22).scaleEffect(1.2)
                    image.resizable().scaledToFit()
                }
            case .failure:
                Color(.secondarySystemFill).overlay {
                    Label(L10n.t("photo.failed"), systemImage: "photo.badge.exclamationmark")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            default:
                Color(.secondarySystemFill).overlay { ProgressView() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .contentShape(Rectangle())
    }
}

/// The photos full screen, swiped as in the carousel; pinch or double tap to zoom.
private struct PhotoViewer: View {
    let name: String
    let photos: [FountainPhoto]
    let url: (String) -> URL?
    @State var index: Int

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        TabView(selection: $index) {
            ForEach(Array(photos.enumerated()), id: \.element.id) { i, photo in
                ZoomablePhoto(url: url(photo.image)).tag(i)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .always : .never))
        .background(.black)
        .ignoresSafeArea()
        .overlay(alignment: .topLeading) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.body.weight(.semibold)).frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: Circle())
            .padding(.leading, 16)
            .accessibilityLabel(L10n.t("ios.close"))
        }
        .overlay(alignment: .topTrailing) {
            if photos.count > 1 {
                Text("\(index + 1) / \(photos.count)")
                    .font(.subheadline).monospacedDigit()
                    .padding(.horizontal, 12).frame(minHeight: 44)
                    .glassEffect(.regular, in: Capsule())
                    .padding(.trailing, 16)
            }
        }
        .environment(\.colorScheme, .dark)
        .accessibilityLabel(name)
    }
}

private struct ZoomablePhoto: View {
    let url: URL?

    @State private var scale: CGFloat = 1
    @State private var base: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var start: CGSize = .zero

    var body: some View {
        AsyncImage(url: url) { phase in
            if case .success(let image) = phase {
                image.resizable().scaledToFit()
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(MagnifyGesture()
                        .onChanged { scale = max(1, min(5, base * $0.magnification)) }
                        .onEnded { _ in
                            base = scale
                            if scale == 1 { withAnimation(.snappy) { offset = .zero; start = .zero } }
                        })
                    // Panning only while zoomed: otherwise the drag is the swipe to the next.
                    .gesture(scale > 1 ? DragGesture()
                        .onChanged { offset = CGSize(width: start.width + $0.translation.width,
                                                     height: start.height + $0.translation.height) }
                        .onEnded { _ in start = offset } : nil)
                    .onTapGesture(count: 2) {
                        withAnimation(.snappy) {
                            scale = scale > 1 ? 1 : 2.5
                            base = scale
                            offset = .zero; start = .zero
                        }
                    }
            } else if case .failure = phase {
                Label(L10n.t("photo.failed"), systemImage: "photo.badge.exclamationmark").foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
