# User Experience Audit — Home, Browser, Library, and Me

This note records concrete behavior and the remaining acceptance gates. It intentionally excludes the reserved Shop surface.

## Home

- Continue Reading is backed by persisted reading progress, not demo entries.
- Resume failures explain when source refresh is required; failed history reads preserve progress.
- Primary hero actions route to live Browser and the local Library.
- Returning to Home refreshes its recent-reading shelf.

## Browser

- Searches go through enabled provider adapters and return partial-source failures honestly.
- Recent submitted queries are stored in the app's local settings table; the list is bounded to six, de-duplicated case-insensitively, and can be cleared.
- Recalling a query submits it again to providers; it does not pretend cached query history is a live result.
- Search-result ranking stays tied to the last submitted query while the input is edited.
- Local filters are removable in one action. Orphan catalog rows without source listings are not allowed into series navigation.
- Query history is optional; a settings write failure must not block a live search.

## Library

- Library membership, reading state and progress remain local.
- Search matches saved titles, alternate titles, creators and edition metadata without making network requests.
- Status filters and persisted sort choices work together with local search.
- Empty-library, no-status-match, no-search-match and storage-error states are distinguished.
- Removing an item remains an explicit, confirmed action; progress is kept separate by the reading-journey service.

## Me

- Reader defaults control the existing persisted right-to-left and long-strip settings used when a chapter is opened.
- A preference write failure rolls the switch back, avoiding a screen that implies an unsaved value is durable.
- Provider toggles serialize user interaction and report failure rather than silently changing presentation state.
- Source diagnostics, repository management and storage management remain real routes.
- Copy states the local-first and source-query boundaries plainly. No fake login, cloud-sync, audio or account controls are exposed.

## Acceptance still required

- Run Flutter analysis, unit/widget tests, Dart Core CI and Android packaging on the PR head.
- Test cold start, search, series opening, reading, progress restoration, filters and settings on a physical Android device.
- Validate search history restoration across app restarts and clearing history on the device.
- Test long-strip and RTL defaults against representative chapters from real sources.
- Keep crash recovery, backup/export, library collections, source-specific request policies, live-source reliability, adaptive performance and immersive audio/voice/haptic runtime as explicit open work until implemented and tested.
