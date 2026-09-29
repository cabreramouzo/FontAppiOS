# iOS permissions

Every permission the app asks the person for, when and where it is asked today, and what
happens without it. It is the base for the onboarding tutorial still to be built (see the
last section). Keep it current when a permission is added or moves.

The purpose strings shown by iOS are in `Info.plist` (and `INFOPLIST_KEY_*` in the
project's build settings), translated in `FontApp/InfoPlist.xcstrings`.

## Summary

| Permission | iOS key / API | Needed for | Asked today | Without it |
|---|---|---|---|---|
| Location, while using | `NSLocationWhenInUseUsageDescription` · `CLLocationManager.requestWhenInUseAuthorization` | Map centred on you, "near me", distance and arrow to a fountain, remote-review check, new fountain pin | Opening the map (`MapScreen.locateOnce`), the locate button, missions, placing a fountain | App works; map opens on the time-zone view, no distances, no "near me" |
| Location, always | `NSLocationAlwaysAndWhenInUseUsageDescription` · `requestAlwaysAuthorization` | "Tell me when I pass a fountain" (region monitoring, `PassingBy`) | Only when that switch is turned on in Settings → Notifications | That feature does not work; the switch shows how to fix it |
| Notifications | `UNUserNotificationCenter.requestAuthorization` (alert, sound, badge) + APNs | Push (a followed fountain went dry, incidents, someone writing to you) and the local "passing by" notice | After following a fountain or posting an incident (`askIfUseful`), from Settings, and when "passing by" is turned on | Only the in-app bell |
| Motion & Fitness | `NSMotionUsageDescription` · `CMMotionActivityManager` | Not asking about a fountain when driving past it | Explainer sheet (`MotionExplainer`) when "passing by" is turned on, or its button in Settings for those who had it on before | Speed of the last fix is used instead; the odd notice while driving |
| Camera | `NSCameraUsageDescription` · `UIImagePickerController` | Taking a fountain's photo | First time "take photo" is used (new fountain, review, gallery, edit) | Choosing from the library still works |

## Not permissions (no prompt)

- **Photo library**: `PhotosPicker` runs out of process and needs no permission; the app
  only gets the photos chosen. Do not add `NSPhotoLibraryUsageDescription`.
- **Keychain** (session token), **Sign in with Apple**, **Associated Domains**
  (`applinks` / `webcredentials:fontapp.net`, passkeys): entitlements, no prompt.
  Passkeys and Sign in with Apple show their own system sheet when the person uses them.
- **Background fetch** (`UIBackgroundModes: fetch`) for the outbox: no prompt; the person
  can turn off Background App Refresh in iOS Settings.

## Rules for the onboarding tutorial

- **Order.** Location "while using" must come before "always": iOS only offers
  "Always" after "While using" has been granted.
- **Each system prompt shows once.** After a refusal, only iOS Settings can change it
  (`UIApplication.openSettingsURLString`). So the tutorial explains first and then
  asks; it never shows the prompt cold.
- **App Review (guideline 5.1.1).** The screen before a prompt may explain, but its button
  must say "Continue" / "Next", never "Allow", and it cannot be skipped by forcing
  a yes. Every permission is optional: "Not now" always lets the person carry on.
- **Push vs bell** (`FontAppBE/CLAUDE.md`): today notifications are never asked at launch,
  only after something that makes a notice worth having. Asking them in the tutorial
  is a product change: decide it there first, and say in the tutorial what will
  and will not arrive (only what changes what you are about to do).
- **"Always" and Motion only matter with "passing by".** Asking them to someone who does
  not want that feature costs trust for nothing. The tutorial should offer the feature
  (one step: "tell me when I pass a fountain?") and ask both only on a yes, reusing
  `PassingBy.setEnabled` and `MotionExplainer`.
- **Camera** is best left to the first photo: the context explains it by itself.
- Anyone who skips the tutorial still gets each prompt where it is asked today, so the
  existing call sites stay.
