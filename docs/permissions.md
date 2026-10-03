# iOS permissions

Every permission the app asks the person for, when and where it is asked today, and what
happens without it. Keep it current when a permission is added or moves.

The purpose strings shown by iOS are in `Info.plist` (and `INFOPLIST_KEY_*` in the
project's build settings), translated in `FontApp/InfoPlist.xcstrings`.

## Summary

| Permission | iOS key / API | Needed for | Asked today | Without it |
|---|---|---|---|---|
| Location, while using | `NSLocationWhenInUseUsageDescription` · `CLLocationManager.requestWhenInUseAuthorization` | Map centred on you, "near me", distance and arrow to a fountain, remote-review check, new fountain pin | Optional first-install tutorial; later the locate button, missions, placing a fountain | App works; map opens on the time-zone view, no distances, no "near me" |
| Location, always | `NSLocationAlwaysAndWhenInUseUsageDescription` · `requestAlwaysAuthorization` | "Tell me when I pass a fountain" (region monitoring, `PassingBy`) | Optional first-install tutorial only after location and notifications are granted; or the switch in Settings → Notifications | That feature does not work; the switch shows how to fix it |
| Notifications | `UNUserNotificationCenter.requestAuthorization` (alert, sound, badge) + APNs | Push (a followed fountain went dry, incidents, someone writing to you) and the local "passing by" notice | Optional first-install tutorial; later after following a fountain or posting an incident (`askIfUseful`) and from Settings | Only the in-app bell |
| Motion & Fitness | `NSMotionUsageDescription` · `CMMotionActivityManager` | Distinguishing someone on foot from someone driving past | Optional tutorial after opting into "passing by"; or `MotionExplainer` in Settings | Uncertain passing-by events do not notify; the rest of the app works |
| Camera | `NSCameraUsageDescription` · `UIImagePickerController` | Taking a fountain's photo | Optional first-install tutorial; otherwise first time "take photo" is used | Choosing from the library still works |
| Photos, add only | `NSPhotoLibraryAddUsageDescription` · `PHPhotoLibrary.requestAuthorization(for: .addOnly)` | Keeping every photo taken with the app's camera in Photos, at full quality, so a failed send never loses it (Settings → "Save the photos I take to Photos", on by default; `PhotoLibrarySaver.saveCameraShot`); saving the photo of a queued contribution ("See my data" → Save photo) | Optional first-install tutorial; otherwise right after the first photo taken with the app's camera, or the first "Save photo". The app cannot read the library | The photo is still used and sent; the Settings toggle says how to allow it. Location is added only if already allowed, never asked for here |

## Not permissions (no prompt)

- **Photo library**: `PhotosPicker` runs out of process and needs no permission; the app
  only gets the photos chosen. Do not add `NSPhotoLibraryUsageDescription`.
- **Keychain** (session token), **Sign in with Apple**, **Associated Domains**
  (`applinks` / `webcredentials:fontapp.net`, passkeys): entitlements, no prompt.
  Passkeys and Sign in with Apple show their own system sheet when the person uses them.
- **iCloud (CloudKit)** for imported GPX routes (`docs/routes.md`): an entitlement, no
  prompt. Without an iCloud account the routes stay on the device. The
  `remote-notification` background mode lets CloudKit's silent pushes bring routes
  changed on another device; it asks nothing and does not need notification permission.
- **Background fetch** (`UIBackgroundModes: fetch`) for the outbox: no prompt; the person
  can turn off Background App Refresh in iOS Settings.

## First-install tutorial

After the six feature pages, a separate optional tutorial explains each permission before
its native request. Each step has Continue and Not now. Location and notifications are
first. The "passing by" step (Always location) appears only when both were granted; its
Motion step appears only after opting in. Camera and add-only Photos follow. An unfinished
tour remains eligible on the next ordinary launch, while a completed one is shown only
once. The controls in Settings and each feature still allow later opt-in.

- **Order.** Location "while using" must come before "always": iOS only offers
  "Always" after "While using" has been granted.
- **Each system prompt shows once.** After a refusal, only iOS Settings can change it
  (`UIApplication.openSettingsURLString`). So the tutorial explains first and then
  asks; it never shows the prompt cold.
- **App Review (guideline 5.1.1).** The screen before a prompt may explain, but its button
  must say "Continue" / "Next", never "Allow", and it cannot be skipped by forcing
  a yes. Every permission is optional: "Not now" always lets the person carry on.
- **Push vs bell** (`FontAppBE/CLAUDE.md`): the tutorial describes the narrow set of
  system notices and the in-app bell. Permission follows only the Continue tap.
- **"Always" and Motion only matter with "passing by".** Asking them to someone who does
  not want that feature costs trust for nothing. The tutorial should offer the feature
  (one step: "tell me when I pass a fountain?") and ask both only on a yes, reusing
  `PassingBy.setEnabled` and `MotionExplainer`.
- Anyone who skips a step can still opt in from its feature or Settings. Existing call
  sites stay.
