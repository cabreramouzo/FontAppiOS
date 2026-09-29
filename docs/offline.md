# Offline on iOS

The product rules are in `FontAppBE/docs/client-rules.md`, section 5 (R5.1–R5.13), read from
the web's offline code. This file says where each one lives in the app and what is native.

| Rule | Where |
|---|---|
| R5.1, R5.5 outbox, owner, order, retries | `Outbox/Outbox.swift` |
| When it is flushed (network back, foreground, sign-in, background) | `Outbox/OutboxSync.swift` |
| R5.6 the notice (states, orange, shrinks after 3 s) | `Outbox/ConnectivityNotice.swift` (logic), `ConnectivityNoticeView.swift` (view, on the map) |
| R5.7 see / copy / save what waits | `Outbox/PendingDetails.swift` (readable text, not JSON), `Outbox/PhotoLibrarySaver.swift` (into Photos) |
| R5.8 discard | `Outbox.discardPlan`, in the notice and in `PendingSection` (profile) |
| R5.9 session without signal | `Session/SessionStore.swift` (`refresh`: only a 401 signs out) |
| R5.14 one notice, not two | `Map/MapScreen.swift` (`banner` hides the error text while `OutboxSync.isOnline` is false) |
| R5.15 photo placeholder and thumbnail | `NewFont/PhotoSlot.swift`, used by `NewFontSheet`; thumbnails in `PendingDetails` and `PendingSection` |
| R5.10 a failed refresh never empties the map | `Map/MapModel.swift`, `OfflineZone.coversHalf` |
| R5.11 saved zones | `Offline/OfflineZones.swift`, `OfflineZonesSheet.swift` |
| R5.12 tiles kept | `Offline/MapTileCache.swift` (+ the zones' MapLibre packs) |
| R5.13 reads and drafts | `Offline/ResponseCache.swift`, `Offline/PinCache.swift`, `Detail/FormDraft.swift` |

## The orange

The web's MUI `warning`: `#ed6c02` on light, `#ffa726` on dark — `Color.warning` (adaptive)
and `Color.onWarning` for text on it. It means "this is not resolved": something waits to be
sent. Only informative states (no signal, nothing pending) are neutral; "all synced" is green.

## Map tiles: how the cache works with vector maps

The map is MapLibre, and MapLibre keeps an **ambient cache** in
`Application Support/<bundle>/.mapbox/cache.db` (iOS never evicts Application Support):
every tile, style, glyph and sprite it downloads goes in, and a resource is asked for again
only after it expires — with an ETag, so an unchanged tile costs a header. Vector tiles are
`.pbf` files per `z/x/y`, cached exactly like raster ones. Past the source's own maximum
zoom (14 for OpenFreeMap, 15 ICGC, 16 IGN base) MapLibre draws the same tile enlarged, so
one download serves several zoom levels.

Two sizes, kept apart on purpose:

- **Ambient cache**: what was seen. `MapTileCache.maxBytes` = 300 MB (MapLibre's default is
  50 MB, filled by a short walk over a raster layer). Least recently used goes first. Set
  at launch, before any map exists. The zones sheet says so and can forget it.
- **Offline packs**: the zones saved on purpose. They do not count against the 300 MB and
  are never removed to make room — the web needed a "pinned" cache to get the same.

Checked 30/09/2026 in the simulator: after one launch over the world view, `cache.db` held
160 tiles / 37 MB.
