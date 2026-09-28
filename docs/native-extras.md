# Native-only extras

Things the PWA cannot do and the iOS app can. None of them is built yet; they come after
the App Store essentials (account deletion, legal links, privacy manifest) and APNs. Each
one keeps the product rules in `FontAppBE/CLAUDE.md`. Above all the push-vs-bell rule
applies: a system notification only for what can change what you are about to do.

Suggested order: the arrival notification and the Live Activity share their machinery
(both follow one chosen fountain in the background), so build them together. Quick actions
are an afternoon. The widget and App Intents need an App Group and a shared cache, and are
the most work.

## 1. "You are there": a notification at 5 m from a fountain

**What.** When you are heading to a fountain you chose, a notification tells you that you
have arrived. It carries the three review chips as actions (flowing · trickle · dry), so
the review is one tap from the lock screen, with the phone still in your pocket until then.

**Why it fits the push rule.** Arriving is the moment the app can help. The photo and the
description say where it is exactly ("behind the kiosk"), and it is the moment a review is
worth most. It is not a notification for every fountain you walk past: a town has dozens,
and that would get the app muted on the first day.

**When it fires.**
- Only for a fountain **you chose to go to**: "Directions", or a new "Take me there" in the
  detail page. It never fires for fountains near your path or for the ones you follow.
- At **5 m real distance**: `RADIO_LLEGADA_M` in `web/src/lib/approach.ts`. It is a real
  distance, not one reduced by accuracy. The web learned that arriving and being able to
  point are separate questions: under trees, ±40 m made it say "you are there" 40 m away.
- Once per trip. It is dropped if you are clearly moving away (> 1 km), and after a time
  limit (say 45 min), so a forgotten trip does not fire hours later.
- Not in the foreground: there the detail page already shows the last-metres guidance
  (arrow under 150 m, "you are there" at 5 m).

**How (no backend involved: it is a local notification).**
- `CLBackgroundActivitySession` started when you tap "Take me there", plus
  `CLLocationUpdate.liveUpdates(.otherNavigation)`. With a session started in the
  foreground, the **"While using"** permission is enough in the background. No "Always" is
  asked for, which Apple reviews carefully and people refuse.
- Region monitoring (`CLMonitor` with a circular condition) is **not** enough alone: the
  system does not resolve regions below ~100 m. It could wake the app at ~150 m to start
  precise updates, but that needs "Always". Keep it as a later option.
- `UNNotificationCategory` with three `UNNotificationAction`s. The action sends the review
  with `confirmIfUnchanged: true` through the outbox, under the account signed in, so it
  also works without signal. Never `unknown` or `gone` among the actions. A notification
  cannot show the 10 s undo, so the review waits in the outbox for those 10 s before it
  is sent, and opening the app within them shows the usual undo.
- Interruption level `.active`, not `.timeSensitive`: nothing is urgent about a fountain.

**Costs and risks.** Battery while the session runs (bounded by the time limit and the
distance cut), and the GPS error: 5 m cannot be told apart from 12 m in a narrow street.
That is why the notification says "you are there" and never "turn left".

## 2. Last metres as a Live Activity

**What.** On the lock screen and in the Dynamic Island: distance and an arrow to the chosen
fountain, updated while you walk. It shows the same three phases as `approach.ts`:
- guiding under 150 m;
- "can't point" when accuracy eats the distance;
- "you are there" at 5 m.

It ends on arrival, and item 1 fires.

**How.** ActivityKit, updated locally from the same background session as item 1 (no push
updates, so no APNs needed). A widget extension target renders it. The arrow needs the
heading; without a compass reading it shows only the distance.

## 3. Home-screen widget: the nearest fountain

**What.** The nearest fountain, its water confidence (confirmed · recent · conflicting ·
old · never checked, never a score) and distance. Tapping opens its detail page. A medium
size lists three.

**How.** WidgetKit with an App Group, so the app shares its last position and the fountains
it last saw. The widget does not ask the server on its own. Timeline reloads are budgeted
by iOS (a few dozen a day), and the map's rate limit (600/h per IP) must not be spent by
widgets. The position is the last one the app knew, labelled as such ("near where you
were at 10:40").

## 4. Siri, Shortcuts and Spotlight (App Intents)

**What.**
- "Is there water near me?": answers with the nearest fountain whose confidence is
  confirmed or recent.
- "Add a fountain here": opens the new-fountain form with the pin at you.
- The offline zones' fountains indexed in Spotlight, so they are found without signal.

**How.** `AppIntent`s over the existing models, plus `AppShortcutsProvider` for the phrases
in the eight languages. Answers must say when data is old: the confidence category travels
with the answer.

## 5. Quick actions on the app icon

Long-press the icon: "Nearest fountain", "Add a fountain", "Without signal" (offline
zones). `UIApplicationShortcutItem` handled in the scene. The cheapest item on this list.

## Already native, for reference

- Background sending of the outbox (`BGTaskScheduler` in `Outbox/OutboxSync.swift`), which
  the PWA cannot do on iOS.
- Offline map packs (MapLibre `MLNOfflineStorage`), which iOS does not evict as it does the
  PWA's caches.
- Location permission that does not expire every 24 h.

## Needs other work first

- **APNs push**: a backend change in FontAppBE (device tokens, APNs sender, `PushCopy`).
- **Passkeys**: `webcredentials:fontapp.net` in Associated Domains, and the
  `apple-app-site-association` file served by the web.
- **Sign in with Apple**: required by App Store rule 4.8 as soon as Google sign-in is
  offered in the app.
