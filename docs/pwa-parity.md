# PWA and iOS feature comparison — 30 September 2026

Compared the current `FontAppBE/web/src/pages` and components, `docs/client-rules.md`,
the latest 50 backend/PWA commit subjects, and the native screens and API client.
The PWA/backend is the source of truth; this file records the current implementation
status, not a second copy of the product rules.

## Implemented in this pass

1. Photo selection in the full review, fountain edit, and other-photo gallery now uses
   the same visible placeholder/thumbnail/reading/error flow as new-fountain creation.
   The prepared JPEG and EXIF metadata are used for both online sending and the review
   outbox instead of preparing the photo a second time at submission.
2. Public places directory and place pages: grouped directory, country filter, the
   region's full list, fountain list with confidence, and nearby places. The entry
   button is hidden for now. Native pages intentionally do not carry the PWA's crawler
   and sitemap code.
3. Support: invite/share, WhatsApp, feedback without requiring sign-in, Aixeta, and BTC
   copy. Reach it from Profile whether signed in or out.
4. Public municipality inventory: exact-name search returns every matching INE code;
   the report shows coverage, priorities, filters, map pins, and shares CSV/GeoJSON.
   Reach it from the places directory.
5. A six-page native feature welcome appears on a fresh installation. It can be skipped,
   and it does not ask for permissions or sign-in. Existing installations are excluded.

## Imported GPX routes — 3 October 2026 (client rule R6.10)

The web keeps **one** route (the last imported, in `localStorage` per account) and shows
it on `/gpx`. iOS goes further, on purpose, because the phone is what goes in the
handlebar mount and is used again on the next outing:

- **A library ("My routes")**, in SwiftData synced through the person's private iCloud;
  never sent to FontApp. The same track imported twice opens the saved one.
- **Every route not hidden is drawn on the map**, each in its colour; one at a time is
  *open* (fountains along it loaded, a chip on the map). Opening one from the list frames
  it; showing, hiding or recolouring never moves the map.
- **Manage in place:** eye to show/hide (per device; hiding also closes it), coloured dot
  to pick one of six colours (closed palette away from water-status and staff colours),
  rename and delete by swipe or context menu. Corridor and excluded fountains are stored
  with each route.
- **"Show only fountains on my routes"** (GPX menu and the route sheet): the map keeps
  just the fountains in the corridor of every visible route (stages of one trip are
  several files), without clusters, so the lines can be read.
- Kept the same as the web: the file is read on the device, only the widened box is
  asked of the server, km order, both ends of the driest stretch, exporting excluded
  ones out.

Web follow-up, if the field data asks for it: the same library (several routes,
visibility and colour) on `/gpx` and the main map. Not needed for parity of the rules,
which R6.10 already states for both.

## Intentionally kept on the web

- The public Zones page and its country/region coverage, pending-fountain lists, local
  goal, and monthly ranking. The existing native saved-offline-zones feature remains.
- The administration panel, including central moderation queues, analytics, users,
  campaigns, and the app-interest dashboard. Existing staff actions on an individual
  fountain remain part of its native detail page.

## Still missing or incomplete

1. **Municipality report follow-ups.** The native map does not yet draw the exact
   municipal boundary, and the report has no dedicated print/PDF layout.
2. **Account recovery.** Password reset still opens the web's email-link flow from the
   native sign-in screen. Native reset-link handling has not been built.
3. **Place follow-ups.** The place page does not yet offer a town-centred map or
   save-the-place shortcut.
4. **What's new.** Release-notes interruptions are not present in native iOS. The PWA's
   app-interest survey asks whether a web visitor wants a native app, so that particular
   survey should not be shown inside the native app.

## Web-only behavior

The install page and prompts, service worker and shell cache, web push transport,
browser safe-area and relayout workarounds, crawler gates, sitemap, and SEO share pages
are web infrastructure rather than native product features. Native iOS already uses
APNs, its own offline stores, and universal links.

## Field test — 2 October 2026

1. **A created fountain came back as the next one's draft.** After creating a fountain
   (online or queued), opening "+" again showed the previous name, choices and pin.
   Cause: the form's model saved the draft on every change, and after sending it kept
   receiving changes while the sheet closed (the precise-location fix that follows the
   user, the small map reporting its centre). The first such write after
   `NewFontDraft.clear` stored the whole old form again, and "+" restored any non-empty
   draft silently. Fixed: once sent, queued or discarded the model never writes the draft
   again; a restored draft is offered (continue / discard, as R2.4 says) instead of
   opening by itself; the toolbar follows Apple's modal-form pattern — **Cancel** on the
   leading side asks "Save draft / Discard" when the form has content, **Create** on the
   trailing side — and the destructive button at the bottom of the form is gone. Covered
   by `NewFontDraftLifecycleTests`.
2. **No photo offer after the quick review.** The web's map popup, after a chip, offers
   "No photo yet. Will you take one? +N drops" when the fountain has none (client rule
   R1.7: status first, then the photo). iOS showed only the thanks. On iOS the chips live
   in the detail sheet's short card, not in a popup of their own, so the offer goes in
   the same place, as one row: the thanks with "No photo yet. Will you take one?" under
   it, the undo beside it, and **Take photo** (prominent: you are in front of it) and
   **Choose photo** right below, also after a review queued without signal. A first
   version used three rows and the buttons fell below the short card, out of sight; it
   also showed "+80 drops", removed so the game does not eclipse the request. It shares the
   page's `PhotoUploadModel`, so a photo taken here is the same one the "no photo yet"
   section shows, and the thanks ("It has a photo now") stays after the page reloads with
   the new cover.
3. **Questions after the quick review fell out of sight.** Each one (photo, then "is it
   drinkable?") was a section added under the chips, and the short card has a fixed
   height: the newest question always landed below its edge. Now the chips' slot is a
   single slot that changes, as the web's popup replaces its content: after the tap it
   shows the thanks (with the undo) and **one** question at a time, in the author's order
   — photo (if none and not reviewed from far away), kind of water, drinkability, name
   (`QuickFlow`). "Not now" / "I don't know" sit beside the question, not under it, and
   the options are one row that scrolls sideways, so each step fits in the chips' height.
   Facts are still asked once per fountain and person; offline only the photo is offered
   (it queues, facts need signal). While the slot asks something, the page below does
   not offer it too (the "Add …" row reads "— unknown —", the "no photo yet" section
   hides): the same question twice looked wrong. To make room in the short card, the
   round action buttons (directions, map, star, share, more) and the "How is it now?"
   title step aside while a question is in the slot, and come back when it is done. Closing the sheet drops the slot's
   state; reopening shows the normal card (chips, "you said so just now"). Raising the
   sheet automatically was discarded: it jumps, covers the map and moves the person's
   sheet without being asked. Covered by `QuickFlowTests`.
