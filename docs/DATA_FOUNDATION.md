# Local-first data foundation

**Status: implemented foundation; user-facing integration is ongoing.** Kurotoon currently stores app-owned data on the device. There is no remote application server, required account or cloud sync. The active app is Flutter/Dart, with SQLite via sqflite; the Dart core defines platform-independent domain models and policies.

## Boundaries

- **Flutter UI:** renders state and dispatches user actions to runtime/application services. It should not issue raw SQL, manage extension manifest files, or bypass domain rules.
- **Runtime/services:** compose providers, durable storage, repository/extension workflows and other adapters.
- **Pure Dart core:** keeps matching, source coordination, progress reconciliation, validation and budget policies testable without Flutter widgets or a live network.
- **SQLite adapter:** durable local records, migrated through explicit schema versions.
- **Managed files:** page/cache/media bytes and installed declarative extension manifests live in bounded app-private files; large binary content does not belong in SQLite.
- **Providers:** retrieve content live. Merely opening comic pages must not silently create a bulk offline archive.

The current KurotoonRuntime.initialize opens the local database, restores provider settings and attempts to load installed declarative extensions. The runtime composition is present; not every domain table/workflow is connected to a finished Flutter screen yet.

## SQLite schema

Current schema version: **2**. The versioned schema includes:

- works and provider_listings for canonical and source-specific metadata.
- editions, chapters and chapter_listings for publication variants and source provenance.
- library_entries and reading_progress for user-owned reading state.
- app_settings and provider_settings for preferences and source enablement.
- creator_profiles and creator_credits for creator attribution.
- identity_review_queue for uncertain possible cross-source matches.
- cache_entries for disposable cache byte/path/LRU/pinned metadata.
- voice_pack_installs for verified pack metadata/installed path.
- extension_repositories and installed_extensions for repository identity and selected declarative installations.

Migrations are append-only. Future changes need an explicit version upgrade and tests that begin from each supported schema. Never delete or rename user-owned records without an explicit migration and safe recovery strategy.

## Storage and privacy rules

1. Keep user-owned state separate from disposable network/media cache.
2. Cache eviction must query only cache entries and their managed files. It must never wipe library, progress, settings, repository trust decisions or extension records as a shortcut.
3. Default cache planning is 1.5 GiB for transient/cache-managed assets; this is not a promise that the entire application stays under 1.5 GiB, nor that cache eviction is fully wired to all writes.
4. Pinned/offline content must be explicitly represented and excluded from eviction. User-initiated offline downloads require visible byte estimates, progress, cancellation and deletion controls.
5. Use managed atomic file writes and clean temporary files after failed installs. Preserve a prior valid installation if a replacement manifest fails validation or database commit.
6. Respect cancellation and size limits while streaming. Do not trust Content-Length alone; count actual bytes received.
7. Handle schema mismatch, database busy/quota/disk-full, unreadable records, deleted files and corrupt cache metadata without making the reader permanently unusable.
8. Report storage capability honestly. Any memory-only fallback is transient, never represented as durable.
9. Do not upload reading history/library metadata by default. There is no hosted sync service currently.
10. Future backup/export must be user-initiated, versioned, validated, previewed before restore and safe against accidental overwrite. Multi-device sync requires a separately designed identity/conflict model.

## Current gaps

- Exercise library/progress/settings and catalog operations end-to-end through the actual Flutter runtime.
- Add migration fixtures from previous schema versions and recovery tests for interruption/app termination.
- Wire the cache budget planner into actual cache writes, eviction and measured disk usage.
- Implement storage-management UI showing used/available bytes, pinned data and per-bucket cleanup.
- Add validated export/import with a dry-run and identity conflict preview before considering cloud sync.
