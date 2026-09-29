# FontApp iOS

Native iOS client for **FontApp**: an app to find drinking **water fountains** nearby
("font" = fountain, not typeface) and report their state (water flowing, little, dry,
broken, gone), with photos, reviews, incidents and a gamification layer.

The web app (PWA) and the backend live in **`/Users/mac/src/FontAppBE`**. That repo is
the source of truth for the API and for every product decision. **Read it; don't copy it
here** — copies go stale. Give this session access to that folder (in the desktop app,
add it as an extra directory; in the terminal, `/add-dir /Users/mac/src/FontAppBE`).

- **Client rules: `FontAppBE/docs/client-rules.md`.** Every product rule a client must
  keep, with who enforces it (server / client / both). Read the sections a screen touches
  **before** building it. When a rule is learnt here (field test, bug), add it there.
- Product rules and the full reasoning behind them: `FontAppBE/CLAUDE.md` (long; search it).
- API contract: `FontAppBE/docs/api.md`. **Partly stale** — when it disagrees with the
  code, the code wins: routes in `Sources/App/routes.swift` and `Sources/App/Controllers/`,
  DTOs next to their controller. The web client's calls in `web/src/api/client.ts` are a
  reliable, current list of what the app actually uses.
- Product plan: `FontAppBE/docs/producto-crecimiento-2026-09.md` (section 14 compares
  native options; FA-09 is "validate the mobile investment").

## Why native iOS, and why first

Decided 27/09/2026. On Android the PWA already behaves like an app (install prompt,
Background Sync, Web Push). On iOS it does not, and that is what native fixes:

- no background sync: queued contributions only send with the app open;
- push only when installed to the home screen, which few people do;
- web location permission expires every 24 h;
- iOS may evict the offline caches;
- WebKit faults we keep working around (tab bar misplaced at launch, stale shell cache).

Audience is roughly half iOS (measured on campaign days, 24–26/09/2026: 53 % iOS among
mobile sessions; quiet days skew iOS because the author's circle uses iPhone).

## What to build first (suggested order)

1. Map with fountains and their state, detail page, "near me" list.
2. Sign in, review in one tap (the three chips), photo, "still the same".
3. Offline outbox (contributions saved on the phone and sent when there is signal).
4. APNs push — needs backend work (see below).

## Backend essentials

- **Base URL (production):** `https://fontapp.fly.dev`. Web is `https://fontapp.net`.
  Local dev: `http://127.0.0.1:8080` (`swift run App serve` in FontAppBE).
- **Auth:** `POST /auth/login` with HTTP Basic (username:password) returns
  `{ token, expiresAt, user }`; then `Authorization: Bearer <token>` everywhere. Token
  lives 30 days. Store it in the **Keychain**. Also `POST /auth/google` (ID token) and
  passkeys under `/auth/passkeys/*` (RP ID `fontapp.net` — a native passkey flow needs
  an Associated Domains `webcredentials:fontapp.net` entry and the matching
  `apple-app-site-association` file served by the web, which does not exist yet).
- **Errors:** JSON with `reason` (Spanish sentence, for humans/logs) and often `code`
  (e.g. `user.emailTaken`). **Translate by `code`**; fall back to `reason` only when the
  code is unknown. Never show a raw key. The keys and texts are in
  `web/src/i18n/dictionaries.ts` as `err.<code>`.
- **Languages:** ca (default), es, gl, eu, en, fr, pt (European), it. All strings of the
  web app are in `web/src/i18n/dictionaries.ts` — reuse the wording, it has been refined.
- **Rate limits:** map reads 600/h per IP; `/activity` and zones 120/h; photo uploads
  30/h per user; new accounts 5 fountains/day. A 429 carries `Retry-After` — show it,
  never retry in a loop.
- **The map:** `GET /fonts/map?minLat&maxLat&minLong&maxLong&width&height` returns
  individual `FontSummary` up to 3,000, and server-side clusters above that. Longitudes
  must be clamped to ±180 and latitudes to ±90 (a world-wide view sends beyond them and
  gets a 400). Throttle reloads while the map follows the user: the web once burned the
  whole hourly limit in 3 s because every GPS fix re-requested the map.
- `fonts.name` can be **null** (3 of 4 imported points have no name): show "unnamed
  fountain" in the reader's language, never invent one.
- Push today is **Web Push** (VAPID) only, in `Sources/App/Push/`. Native needs **APNs**:
  a device-token table (or a platform column on `push_subscriptions`), an APNs sender
  (token-based auth, .p8 key as a Fly secret) and the same `PushCopy` texts. Plan it as
  a backend change in FontAppBE, not here.

## Product rules the app must keep

These are decisions, not accidents. Each has its reasoning in `FontAppBE/CLAUDE.md`.

- **Push vs bell.** A system notification only for what can change what you are about to
  do (a fountain you follow went dry, an incident, someone talking to you). Everything
  else (likes, "still the same" on your review, levels) goes to the in-app bell only. An
  app gets muted once and never unmuted.
- **Water confidence** is a category, not a score: confirmed · recent · conflicting ·
  old · never checked (`web/src/lib/confidence.ts`). "Conflicting" beats the last state.
  Freshness window 30 days.
- **One-tap review:** three chips — flowing, trickle, dry. Never `unknown` or `gone` in a
  shortcut (two `gone` reports from different people retire a fountain). Send
  `confirmIfUnchanged: true`: the server turns it into a "still the same" when it repeats
  a recent report by someone else. Undo for 10 s.
- **Remote review:** if the position says you are clearly far (> 1 km after subtracting
  accuracy), ask "have you seen it recently?" once per fountain, and send
  `remoteDistanceM`. Never block. Only with location permission already granted.
- **New fountain:** the pin starts at the user if the map centre is within 250 m, else at
  the map centre. Warn if another fountain is within 25 m, naming it and the metres.
- **Outbox:** contributions made without signal are stored with the **account that made
  them** and only sent under that account. Photos are compressed and keep their EXIF
  date/GPS as separate fields (`POST /images` meta), because re-encoding strips EXIF.
- **Drafts:** a half-filled form survives the app being killed; closing the form keeps
  the draft, sending or an explicit discard removes it.
- **Last metres** (`web/src/lib/approach.ts`): arrow to the fountain under 150 m, stop
  pointing when accuracy makes it a lie, "you are there" only within 5 m real distance.
- **Staff accounts** (moderator and above) see the map buttons in staff purple
  (`#7c3aed`) so they do not contribute as admin by mistake.
- Touch targets ≥ 44 pt; the web uses 48 px for thumb controls.
- Data licence: OpenStreetMap (ODbL) and ICGC/ACA (CC BY 4.0) must be attributed on the
  map; community data is ODbL, photos CC BY-SA 4.0.

## What NOT to port

Web/PWA workarounds that do not exist natively — don't reimplement them:
service-worker caching and shell versioning, `lib/iosRelayout.ts` (tab bar at launch),
`lib/staleChunk.ts` (stale bundles), the safe-area probe, the install page and install
prompts, `localStorage` quirks, the crawler gate and Pages Functions (SEO/share cards).

## Conventions

- Code, names and comments in **English**; commit messages in English, ending with the
  `Co-Authored-By` line the session provides. Talk to the author in Spanish.
- Don't add dependencies without saying why.
- Never hard-code secrets. Nothing from local seeded data counts as a real figure: the
  local database is seeded, production is not.
