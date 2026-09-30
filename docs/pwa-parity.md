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
