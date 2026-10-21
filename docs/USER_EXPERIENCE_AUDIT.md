# User Experience Audit — Home, Browser, Library, and Me

This note records concrete behavior and the remaining acceptance gates. It intentionally excludes the reserved Shop surface.

## Home

- Continue Reading is backed by persisted reading progress, not demo entries.
- Resume failures explain when source refresh is required; failed history reads preserve progress.
- Primary hero actions route to live Browser and the local Library.
- Returning to Home refreshes its recent-reading shelf.

## Browser

- Stories search goes through enabled provider adapters and returns partial-source failures honestly.
- A Stories / Creators selector adds creator search over the bounded local creator index; creator pages list aliases and up to 50 credited catalog works without pretending to fetch a biography or issuing a network request.
- Recent submitted queries are stored in the app's local settings table; the list is bounded to six, de-duplicated case-insensitively, and can be cleared.
- Recalling a query submits it again to providers; it does not pretend cached query history is a live result.
- Search-result ranking stays tied to the last submitted query while the input is edited.
- Local filters are removable in one action. Orphan catalog rows without source listings are not allowed into series navigation.
- Query history is optional; a settings write failure must not block a live search.

## Library

- Library membership, reading state and progress remain local.
- Search matches saved titles, alternate titles, creators and edition metadata without making network requests.
- Status filters and persisted sort choices work together with local search.
- Manual ordering is available when the full library is shown; filtered, collection-scoped, or searched views cannot save partial order. The database transaction rejects stale identities and duplicates without changing the prior ordering.
- Custom collections are stored in SQLite with a versioned schema migration; collection names are normalized and unique, memberships are idempotent, and users can create/select/delete a collection or add/remove one saved edition without making network requests.
- Deleting a collection removes only its membership organization; deleting a saved library entry cleans its memberships but does not erase separate reading progress.
- Empty-library, empty-collection, no-status-match, no-search-match and storage-error states are distinguished.
- Removing an item remains an explicit, confirmed action; progress is kept separate by the reading-journey service.

## Me

- Reader defaults control the persisted right-to-left, long-strip and data-saver preferences used by the reader.
- Reader-toolbar preference writes are serialized and persisted before applying the visible setting, avoiding races and UI/disk divergence on failed writes.
- A preference write failure rolls the switch back, avoiding a screen that implies an unsaved value is durable.
- Provider toggles serialize user interaction and report failure rather than silently changing presentation state.
- Source diagnostics, repository management and storage management remain real routes.
- Copy states the local-first and source-query boundaries plainly. No fake login, cloud-sync, audio or account controls are exposed.

## Cache and storage recovery

- Each managed cache write/removal persists an operation journal before moving existing files.
- The journal is deleted inside the same SQLite transaction as the cache metadata commit, so a surviving journal unambiguously signals that recovery is required.
- Cache-service startup replays pending operations, restoring staged backups and removing uncommitted targets; successful recovery cleans abandoned pending files and unindexed cache targets.
- Recovery validates paths against the managed cache root and rejects symlinks. It only handles disposable cache bytes and cache metadata; saved stories and reading progress are not used as rollback targets.
- Migration from schema version 7 creates the journal table without dropping existing cache entries.
- If recovery cannot safely reconcile a file, its journal is retained for a later retry and the cache maintenance pass does not block Library/Reader access.

## Storage management

- The Storage & Cache screen shows indexed cache footprint and protected bytes separately from the local Library and reading progress.
- Cache integrity status reports interrupted operations recovered, pending files removed, backup files reconciled, unindexed cache files removed, and unresolved errors.
- Users can explicitly rerun the managed-cache recovery pass. It operates only on disposable cache content and corresponding cache metadata.
- A recovery problem is shown separately from cache-index loading and never implies that saved stories or reading progress were modified.
- A read-only budget gauge compares indexed cache bytes with the configured cache ceiling. A selectable hypothetical item size runs the existing eviction policy as a dry run and reports whether the write is feasible and how many unpinned items would be removed; it does not mutate cache data.
- Long-session storage telemetry and physical-device pressure testing remain open.

## Provider diagnostics export

- Source Diagnostics supports a versioned JSON export through an explicit preview-and-copy flow.
- The export uses a strict allowlist of source identity, display label, health state/capabilities, failure counts, status timestamps and remaining cooldown.
- The export omits raw exception/stack text, HTTP requests/responses/headers, full URLs/paths, searches, story/creator titles, library membership, progress and credentials. Suspicious URL/token-like text embedded in source labels is redacted.
- Nothing is uploaded. The user sees the exact JSON and is told that enabled-source names and health timing remain visible before copying.

## Acceptance still required

- Run Flutter analysis, unit/widget tests, Dart Core CI and Android packaging on the PR head.
- Test cold start, search, series opening, reading, progress restoration, filters and settings on a physical Android device.
- Validate search history restoration across app restarts and clearing history on the device.
- Verify local creator-index rebuild performance and creator-work aggregation on a realistic catalog.
- Test long-strip and RTL defaults against representative chapters from real sources.
- Verify collection schema migration, create/add/remove/delete semantics on device and after process restart (automated database tests are included with this change).
- Keep crash recovery, backup/export, manual drag ordering, source-specific request policies, live-source reliability, adaptive performance and immersive audio/voice/haptic runtime as explicit open work until implemented and tested.
