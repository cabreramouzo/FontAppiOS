# FontAppiOS
FontApp client for iOS

## Build number

Release builds set `CFBundleVersion` to the git commit count
(`scripts/set-build-number.sh`, run by a build phase in the app and the widget), so
there is nothing to bump before archiving. Commit first: two archives of the same
commit get the same number. `CURRENT_PROJECT_VERSION` only matters for Debug.
