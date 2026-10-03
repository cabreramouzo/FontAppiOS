# Open design questions

Questions to discuss later, not decisions. Each one says what prompted it and what is
known so far. When one is decided, move the decision where it belongs (code comment,
`FontAppBE/docs/client-rules.md`, or the feature's doc) and remove it from here.

## Too many buttons in the map's right column? (3 October 2026)

**The thought.** The glass column at the top right of the map (`Map/MapControls.swift`)
does not get in the way, but it holds many options: layers, filters, legend, missions,
offline maps, GPX (water on my route, my routes, show only fountains on my routes, export),
plus location below. Some of them are not things done while looking at the map, so they
may belong somewhere else, or they may be fine where they are.

**To discuss one day.**
- Which options are used *on* the map (layers, filters, legend, location) and which are
  occasional tasks (GPX import and export, my routes, downloading offline maps,
  missions) that could live in another place: a "more" menu, the profile/settings tab,
  or a tools sheet.
- What the field data says: how often each button is used, before moving anything.
- Discoverability: a button on the map is found; one in a menu may never be.

**Constraints if it changes.** The map help tour must change in the same commit (a
`MapHelpTarget` case, its `ios.mapHelp.<key>` text in the 8 languages, the
`.mapHelpTarget(...)` marker), checked in the simulator on a small iPhone and in Basque
(CLAUDE.md). Touch targets stay ≥ 44 pt. The GPX button keeps its letters (web decision).

Nothing to do for now.
