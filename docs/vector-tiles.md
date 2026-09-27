# ICGC and IGN as vector tiles on iOS

Spike of 27/09/2026. Question: can the app show the ICGC and IGN base maps as vector
tiles instead of raster, as the author asked ("siempre es mejor")?

## What the servers offer

| Source | Tiles | Style JSON | Coverage |
|---|---|---|---|
| ICGC ContextMaps | `https://geoserveis.icgc.cat/servei/catalunya/mapa-base2/vt/{z}/{x}/{y}.pbf` (OpenMapTiles schema, max zoom 15) | `https://geoserveis.icgc.cat/contextmaps/icgc.json` (148 layers, own glyphs and sprites) | Catalonia in detail, the rest of the world from OSM |
| IGN Mapa base (SCN) | `https://vt-mapabase.idee.es/1.0.0/mapabase/{z}/{x}/{y}.pbf` | `https://vt-mapabase.idee.es/files/styles/mapaBase_scn_color1_CNIG.json` (587 layers, hillshade from the DEM) | Spain only (403 outside) |
| IGN BTN (topographic) | `https://vt-btn.idee.es/1.0.0/btn/tile/{z}/{y}/{x}.pbf` (note `{y}/{x}`) | `https://vt-btn.idee.es/files/styles/BTN_Completa.json` (337 layers) | Spain only (404 outside) |

Styles list: https://www.ign.es/web/estilos-de-los-servicios-de-teselas-vectoriales.
Licence: CC BY 4.0 for both institutes' data. Attribution as today.

All three styles load **without errors** in MapLibre GL JS 5 (checked in a browser, same
style engine as MapLibre Native); screenshots in the session.

## Size, measured over Moià (41.80–41.82 N, 2.09–2.11 E)

| Layer | What an offline zone saves | Size |
|---|---|---|
| ICGC raster | z15–17, 124 tiles | **9.3 MB** |
| ICGC vector | z14 (overzoomed above), 4 tiles | **0.3 MB** |
| IGN MTN raster | z15–17, 124 tiles | 1.6 MB |
| IGN mapa base vector | z14–16, 38 tiles | 0.8 MB |

Vector is ~30× smaller for ICGC. For offline zones — the feature that matters most on
iOS — that is the difference between a comarca and a village. It is also sharp at every
zoom and rotates with readable labels.

## Why it is not in the app yet: MapKit cannot draw it

`MKMapView` draws only Apple's maps and raster overlays (`MKTileOverlay`). There is no
vector tile or style support. The options:

1. **MapLibre Native iOS** (BSD-2, free, no API key; Swift Package
   `maplibre/maplibre-gl-native-distribution`). Renders these styles as they are,
   including glyphs, sprites, hillshade and offline packs (`MLNOfflineStorage`), which
   would replace `TileStore` for these layers.
   - Cost: one dependency (~10 MB in the binary) and a second map view. The pins,
     clusters, route and user location would have to be re-done on MapLibre (as style
     layers or annotations), or the whole map moves to MapLibre and MapKit stays only
     for Apple's own base map. Either way it is a real piece of work, not a layer swap.
   - The project rule is not to add dependencies without saying why: this is the why.
2. **Rasterise on the phone** (decode PBF and draw into `MKTileOverlay` tiles): means
   writing a style renderer. Not reasonable.
3. **Keep raster** (what ships now): works today with MapKit, same look as the web, but
   heavier offline and blurrier when zoomed past the tile level.

## Recommendation

Go to MapLibre Native as its own iteration, moving the whole map to it (one engine for
pins, clusters, route and base map, and offline packs for free), with Apple's map kept
only as a base layer choice through MapKit if it is still wanted. Do it after the
features settle, since it rewrites `FontMapView`. Until then the raster layers are the
safe choice and share the same URLs' licences and attribution.
