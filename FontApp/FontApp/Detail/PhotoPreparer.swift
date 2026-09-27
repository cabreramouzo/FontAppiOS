import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Turns a picked photo into what `POST /images` takes: a JPEG no larger than it needs to
/// be, plus the EXIF date and position as separate fields.
///
/// The order is the point: re-encoding drops every piece of metadata, so the EXIF is read
/// from the original first. Doing it the other way round fails silently — nothing breaks,
/// and months later no photo has a date (see `prepararFoto` in `web/src/lib/image.ts`).
nonisolated enum PhotoPreparer {
    /// Long side in pixels. Enough to recognise a fountain and its sign; the server takes
    /// up to 8 MB, and at this size a JPEG stays far below it.
    static let maxPixelSize = 2048
    static let quality = 0.8

    struct Prepared: Sendable {
        let jpeg: Data
        let meta: PhotoMeta
    }

    enum Failure: Error { case unreadable }

    static func prepare(_ original: Data) throws -> Prepared {
        guard let source = CGImageSourceCreateWithData(original as CFData, nil) else { throw Failure.unreadable }
        let meta = metadata(of: source)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            // Applies the EXIF orientation to the pixels, since the tag itself is dropped.
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw Failure.unreadable
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw Failure.unreadable }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw Failure.unreadable }
        return Prepared(jpeg: output as Data, meta: meta)
    }

    /// The capture date (with its offset when the camera wrote one) and GPS position.
    static func metadata(of source: CGImageSource) -> PhotoMeta {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return PhotoMeta()
        }
        var meta = PhotoMeta()
        if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
           let original = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
            meta.takenAt = exifDate(original, offset: exif[kCGImagePropertyExifOffsetTimeOriginal] as? String)
        }
        if let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any],
           let lat = gps[kCGImagePropertyGPSLatitude] as? Double,
           let lon = gps[kCGImagePropertyGPSLongitude] as? Double {
            let south = (gps[kCGImagePropertyGPSLatitudeRef] as? String) == "S"
            let west = (gps[kCGImagePropertyGPSLongitudeRef] as? String) == "W"
            meta.latitude = south ? -lat : lat
            meta.longitude = west ? -lon : lon
        }
        return meta
    }

    /// EXIF writes "2026:09:27 10:15:03" in the camera's local time, with the offset
    /// ("+02:00") in a separate tag. Without the offset, the device's time zone is the
    /// best guess: the photo was almost always taken where the phone is.
    static func exifDate(_ text: String, offset: String?, timeZone: TimeZone = .current) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        if let offset {
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ssXXX"
            return formatter.date(from: text + offset)
        }
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.timeZone = timeZone
        return formatter.date(from: text)
    }
}
