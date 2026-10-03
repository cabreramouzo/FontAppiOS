# Imported GPX routes ("Water on my route")

What the person sees, how it is stored and synced, and what to set up before shipping.
The product rule shared with the web is **R6.10** in `FontAppBE/docs/client-rules.md`;
how iOS differs from the web is in `docs/pwa-parity.md`.

## What it does

- **Import** a `.gpx` (track or route, never waypoints) from the GPX button → "Water on my
  route", from Files, or opened from another app (Wikiloc, Mail, AirDrop: the app
  registers `com.topografix.gpx`). The file is read on the phone; only the route's box,
  widened by the widest corridor, is asked of the server (saved offline zones without
  signal). The map frames the route and its sheet opens.
- **The route sheet**: fountains along it by kilometre with their detour, the driest
  stretch (both ends counted, and again counting only water on record), the longest dry
  climb, the elevation profile, the corridor (100 m – 1 km), which fountains go to the GPS
  file, and the export. Also: *Show only fountains on the route*, hide, delete, and "My routes".
- **On the map**: every route not hidden is drawn, each in its colour. One at a time is
  *open*: its fountains are loaded and a **chip** under the (?) names it. Tapping the chip
  opens the sheet; the eye hides the line; the cross closes it (still saved). A line
  nobody explains was a surprise in the field (03/10/2026); the chip is the explanation.
- **My routes** (GPX menu, once one is saved; or from the route sheet): every imported
  route, newest first, under a standing hint ("tap a route to open it…"; not a TipKit tip:
  the list is opened now and then and a dismissed tip never comes back). Tap to open it and frame the map; coloured dot to pick a colour;
  swipe or long press to rename or delete (delete asks first: it removes it from every
  device with the same iCloud). Importing the same track again opens the saved one.
- **Show only fountains on the route** (GPX menu while a route is open, and the route sheet):
  the map shows only the fountains inside the open route's corridor and no cluster
  bubbles, so the line can be read. Filters still apply on top. It is per device and
  remembered for the next route; with no route open it does nothing.
  *Why not smaller pins or "hide all fountains":* smaller pins break the 44 pt touch
  target and the cluster numbers stop being legible; hiding every fountain hides the very
  thing the route is for. Why not in Filters: Filters is the map's standing view; this
  is temporary and belongs to the route.

## Storage and sync

- `Routes/SavedRoute.swift`: a SwiftData model. Name, import date, length, corridor,
  excluded fountains, colour, a fingerprint (to spot the same track), and the simplified
  track packed as Float64 triples (`RouteCodec`; elevation NaN when missing — flat and
  unknown are not the same) in external storage.
- `Routes/RouteLibrary.swift`: one store, synced with the **private** CloudKit database
  `iCloud.net.fontapp.FontApp`. If the CloudKit container cannot be opened, the same
  file is opened without sync: routes are kept, only not synced. Changes from other
  devices arrive through `NSPersistentStoreRemoteChange`.
- **Synced** (they belong to the route): name, colour, corridor, excluded fountains,
  deletion. **Per device** (`UserDefaults`): which route is open, which are hidden, and
  *show only fountains on the route*. Hiding a route on the iPad must not take it off the
  iPhone in someone's handlebar mount.
- CloudKit rules the model keeps: every property has a default, nothing unique, no
  relationships. A new property must keep those rules, and the schema must be deployed
  again (below).
- The library keeps a reference to its `ModelContainer`: a `ModelContext` does not retain
  it, and a context whose container is gone crashes on the first fetch (seen 03/10/2026).
- Privacy: FontApp's server never receives a route. The texts say "this device and your
  iCloud" (`ios.gpx.privacy`, `ios.routes.icloud`), or "this device only" when the device
  has no iCloud account (`ios.routes.local`).

## Setup before shipping

1. **Xcode → Signing & Capabilities → iCloud**: CloudKit on, container
   `iCloud.net.fontapp.FontApp` (Xcode creates it in the developer account the first time).
   The entitlements are in `FontApp.entitlements`; `UIBackgroundModes` has
   `remote-notification` for CloudKit's silent pushes.
2. **CloudKit Console → Deploy Schema Changes to Production** before any TestFlight or App
   Store build. Debug builds create the schema in *Development* only; without the deploy,
   production devices do not sync. Repeat after any change to `SavedRoute`.
3. Without either, the app still works: routes are kept on the device.

## Testing

Unit tests: `RouteLibraryTests` in `FontAppTests` (packing round trip, duplicate import,
choices stored with the route, deleting the open route). By hand: import, chip (eye,
cross, long name in Basque on a small iPhone), My routes (open, colour menu shows each
colour, rename, delete), *show only fountains on the route* on and off, relaunch keeps
everything, two devices on the same Apple ID, and the map help tour with and without a
route open (the route step appears only when the chip is on screen).
