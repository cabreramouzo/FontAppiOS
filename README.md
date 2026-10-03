# FontAppiOS
FontApp client for iOS

## Build number

Release builds set `CFBundleVersion` to the git commit count
(`scripts/set-build-number.sh`, run by a build phase in the app and the widget), so
there is nothing to bump before archiving. Commit first: two archives of the same
commit get the same number. `CURRENT_PROJECT_VERSION` only matters for Debug.

## Widgets

«Fuentes cerca» and «Fuente favorita» coexist. Add a favorite in FontApp, add the
favorite widget from the system gallery, then use Edit Widget to choose the fountain.
The medium widget supports up to three distinct favorites, each linking to its details.
All sizes show the status emoji and label the date as “Last report”.
Several instances can show different favorites. The date belongs to the water report;
iOS decides when periodic refreshes run.

Both app and extension require App Groups with `group.net.fontapp.FontApp` in their
signing profiles. Product rules and deferred Apple ideas live in the backend repository:
[Apple ecosystem ideas](../FontAppBE/docs/apple-ecosystem-ideas.md).
