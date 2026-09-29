import Foundation
import MapLibre

/// The tiles the map has drawn, kept on the phone so a part already seen is never
/// downloaded again and is still there without signal (rule R5.12).
///
/// MapLibre does this by itself — its *ambient cache* stores every tile, style, glyph and
/// sprite it fetches, and asks the server again only when what it has has expired (and then
/// with an ETag, so an unchanged tile costs a header, not the tile). What it gets wrong is
/// the size: the default is 50 MB, which a walk over the IGN topographic raster (~20 KB a
/// tile) fills in a couple of screens, and then the tiles seen yesterday go.
///
/// Vector tiles need no other treatment. A vector tile is a `.pbf` per `z/x/y` like a raster
/// one, cached the same; and past the source's own maximum zoom MapLibre draws the same tile
/// larger, so one download serves several zoom levels (that is why vector zones are ~30×
/// lighter, see `docs/vector-tiles.md`).
///
/// The zones saved on purpose are separate: their offline packs do not count against this
/// size and are never removed to make room — what was prepared on Friday is still there on
/// Saturday after looking at another valley. The web needed a "pinned" cache for that.
@MainActor
enum MapTileCache {
    /// About 15,000 raster tiles or several hundred thousand vector ones. The web keeps
    /// 3,000 (~18 MB); a phone today holds far more, and it is dropped least-recently-used.
    static let maxBytes: UInt = 300 * 1024 * 1024

    /// Before any map is created: MapLibre asks for it to be set before a style loads.
    static func configure() {
        MLNOfflineStorage.shared.setMaximumAmbientCacheSize(maxBytes) { _ in }
    }

    /// Forgets what the map has seen. Saved zones are not touched.
    static func clear() async {
        try? await MLNOfflineStorage.shared.clearAmbientCache()
    }
}
