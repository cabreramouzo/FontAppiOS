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
    @Namespace private var zoom

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TabView(selection: $index) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { i, photo in
                    Button { viewing = i } label: {
                        FilledPhoto(url: url(photo.image)).matchedTransitionSource(id: photo.id, in: zoom)
                    }
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
            // Swiping in the viewer pages the carousel too, so closing shrinks the photo
            // back into the page it came from.
            PhotoViewer(name: name, photos: photos, url: url, index: v.index, onIndex: { index = $0 })
                .navigationTransition(.zoom(sourceID: photos[min(index, photos.count - 1)].id, in: zoom))
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
                    if let user = review.username { UserLink(username: user).font(.footnote) }
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
/// Dragged up or down (unzoomed), the photo follows the finger and shrinks; let go far
/// enough and the system's zoom transition takes it back into its thumbnail, as Photos.
struct PhotoViewer: View {
    let name: String
    let photos: [FountainPhoto]
    let url: (String) -> URL?
    @State var index: Int
    var onIndex: (Int) -> Void = { _ in }
    /// Zoomed in, a drag pans the photo instead of closing the viewer.
    @State private var zoomed = false
    /// The drag to close, as it goes.
    @State private var drag: CGSize = .zero

    /// The web's distance to close (`CIERRE_V` in `ZoomableImage.tsx`).
    private static let closeDistance: CGFloat = 90
    private var progress: CGFloat { min(1, hypot(drag.width, drag.height) / 400) }

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        TabView(selection: $index) {
            ForEach(Array(photos.enumerated()), id: \.element.id) { i, photo in
                ZoomablePhoto(url: url(photo.image), isCurrent: i == index, onZoom: { zoomed = $0 },
                              onDrag: { drag = $0 }, onRelease: release).tag(i)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: photos.count > 1 && drag == .zero ? .always : .never))
        .scaleEffect(1 - progress * 0.45)
        .offset(drag)
        .background { Color.black.opacity(1 - progress).ignoresSafeArea() }
        .ignoresSafeArea()
        // The page shows through while the photo is dragged away.
        .presentationBackground(.clear)
        .interactiveDismissDisabled(zoomed)
        .onChange(of: index) { _, i in zoomed = false; onIndex(i) }
        .overlay(alignment: .topLeading) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.body.weight(.semibold)).frame(width: 44, height: 44)
            }
            .glassButton(in: Circle())
            .padding(.leading, 16)
            .opacity(drag == .zero ? 1 : 0)
            .accessibilityLabel(L10n.t("ios.close"))
        }
        .overlay(alignment: .topTrailing) {
            if photos.count > 1 {
                Text("\(index + 1) / \(photos.count)")
                    .font(.subheadline).monospacedDigit()
                    .padding(.horizontal, 12).frame(minHeight: 44)
                    .glassEffect(.regular, in: Capsule())
                    .padding(.trailing, 16)
                    .opacity(drag == .zero ? 1 : 0)
            }
        }
        .environment(\.colorScheme, .dark)
        .accessibilityLabel(name)
    }

    /// Far enough (or flicked): closed from where it is, shrinking into the thumbnail.
    /// Not far enough: back to its place.
    private func release(_ translation: CGSize, _ velocity: CGSize) {
        if hypot(translation.width, translation.height) > Self.closeDistance || abs(velocity.height) > 900 {
            dismiss()
        } else {
            withAnimation(.spring(duration: 0.3)) { drag = .zero }
        }
    }
}

/// One photo in the viewer, on a `UIScrollView`: the system's own pinch (around the
/// fingers), pan with inertia and edge bounce, and double tap to zoom on the tapped
/// point. Unzoomed, the scroll view has nothing to scroll, so the horizontal drag falls
/// through to the pager and swipes to the next photo.
private struct ZoomablePhoto: View {
    let url: URL?
    var isCurrent = true
    var onZoom: (Bool) -> Void = { _ in }
    var onDrag: (CGSize) -> Void = { _ in }
    var onRelease: (CGSize, CGSize) -> Void = { _, _ in }

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image {
                ZoomScrollView(image: image, isCurrent: isCurrent, onZoom: onZoom, onDrag: onDrag, onRelease: onRelease)
            } else if failed {
                Label(L10n.t("photo.failed"), systemImage: "photo.badge.exclamationmark").foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: url) {
            image = nil; failed = false
            guard let url else { failed = true; return }
            if let (data, _) = try? await URLSession.shared.data(from: url), let loaded = UIImage(data: data) {
                image = loaded
            } else if !Task.isCancelled {
                failed = true
            }
        }
    }
}

/// Reports its layout so the image can be fitted once the page has its real size
/// (`makeUIView` runs before that).
private final class FittingScrollView: UIScrollView {
    var onLayout: (() -> Void)?
    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}

private struct ZoomScrollView: UIViewRepresentable {
    let image: UIImage
    let isCurrent: Bool
    let onZoom: (Bool) -> Void
    let onDrag: (CGSize) -> Void
    let onRelease: (CGSize, CGSize) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = FittingScrollView()
        scroll.delegate = context.coordinator
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.bouncesZoom = true
        scroll.backgroundColor = .clear
        scroll.maximumZoomScale = 5

        let view = UIImageView(image: image)
        view.contentMode = .scaleAspectFit
        view.isUserInteractionEnabled = true
        scroll.addSubview(view)
        context.coordinator.imageView = view
        context.coordinator.scroll = scroll
        scroll.onLayout = { [weak c = context.coordinator] in c?.layoutIfNeeded() }

        let double = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTapped(_:)))
        double.numberOfTapsRequired = 2
        view.addGestureRecognizer(double)

        // The drag to close. The system's own (on the zoom transition) never starts here:
        // the pager takes the touch first.
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.dragged(_:)))
        pan.delegate = context.coordinator
        scroll.addGestureRecognizer(pan)
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        let c = context.coordinator
        if c.imageView?.image !== image { c.imageView?.image = image }
        c.onZoom = onZoom
        c.onDrag = onDrag
        c.onRelease = onRelease
        // Swiped away zoomed in: back to whole, so coming back finds the full photo.
        if !isCurrent, scroll.zoomScale > 1 { scroll.setZoomScale(1, animated: false) }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        weak var scroll: UIScrollView?
        weak var imageView: UIImageView?
        var laidOutSize: CGSize = .zero
        var onZoom: (Bool) -> Void = { _ in }
        var onDrag: (CGSize) -> Void = { _ in }
        var onRelease: (CGSize, CGSize) -> Void = { _, _ in }
        private var wasZoomed = false

        /// Only unzoomed and for a clearly vertical drag: zoomed, the drag pans the photo;
        /// sideways, it is the pager's swipe to the next one.
        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            guard let pan = gesture as? UIPanGestureRecognizer, pan !== scroll?.panGestureRecognizer,
                  let scroll else { return true }
            guard scroll.zoomScale <= 1.01 else { return false }
            let v = pan.velocity(in: scroll)
            return abs(v.y) > abs(v.x) * 1.5
        }

        @objc func dragged(_ pan: UIPanGestureRecognizer) {
            let t = pan.translation(in: pan.view?.window)
            switch pan.state {
            case .changed:
                onDrag(CGSize(width: t.x, height: t.y))
            case .ended:
                let v = pan.velocity(in: pan.view?.window)
                onRelease(CGSize(width: t.x, height: t.y), CGSize(width: v.x, height: v.y))
            case .cancelled, .failed:
                onRelease(.zero, .zero)
            default:
                break
            }
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            center()
            let zoomed = scrollView.zoomScale > 1.01
            // Unzoomed there is nothing to pan, and a pan that begins anyway takes the
            // drag down from the system's close-by-zooming-back gesture.
            scrollView.panGestureRecognizer.isEnabled = zoomed
            if zoomed != wasZoomed { wasZoomed = zoomed; onZoom(zoomed) }
        }

        /// The image is fitted to the page at scale 1 (zoom scales are relative to that),
        /// and re-fitted when the page changes size (rotation).
        func layoutIfNeeded() {
            guard let scroll, let imageView, scroll.bounds.size != .zero, scroll.bounds.size != laidOutSize else { return }
            laidOutSize = scroll.bounds.size
            scroll.zoomScale = 1
            imageView.frame = CGRect(origin: .zero, size: scroll.bounds.size)
            scroll.contentSize = scroll.bounds.size
            scroll.panGestureRecognizer.isEnabled = false
            center()
        }

        /// Smaller than the page (a zoom under 1 while pinching): keep it centred.
        private func center() {
            guard let scroll, let imageView else { return }
            let x = max(0, (scroll.bounds.width - imageView.frame.width) / 2)
            let y = max(0, (scroll.bounds.height - imageView.frame.height) / 2)
            scroll.contentInset = UIEdgeInsets(top: y, left: x, bottom: y, right: x)
        }

        @objc func doubleTapped(_ gesture: UITapGestureRecognizer) {
            guard let scroll, let imageView else { return }
            if scroll.zoomScale > 1.01 {
                scroll.setZoomScale(1, animated: true)
            } else {
                let target: CGFloat = 2.5
                let point = gesture.location(in: imageView)
                let size = CGSize(width: scroll.bounds.width / target, height: scroll.bounds.height / target)
                scroll.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                                       width: size.width, height: size.height), animated: true)
            }
        }
    }
}
