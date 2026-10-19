# Local-first data foundation

**Status: implemented foundation; application integration is ongoing.**

Kurotoon has no remote application server today. Its first durable backend is the client-side data layer, designed for PWA and Capacitor Android to share the same contracts without forcing an account or uploading personal reading history. A hosted sync service is a separate future decision and must not be simulated by local code.

## Boundaries

- **UI** renders and sends user actions to application services; it should not open IndexedDB or write directly to browser storage.
- **Application repositories** own library membership, reading progress, and settings rules.
- **DataStore** is the persistence port used by repositories.
- **IndexedDbDataStore** is the default durable browser/Android-WebView adapter.
- **MemoryDataStore** is a deterministic test adapter and a last-resort runtime fallback. Its `mode` is explicitly `memory`; it must never be represented to a user as durable storage.
- **Providers** remain network adapters. Comic pages and source responses are not copied into the durable library database just because they're viewed.

## Versioned database

Database: `kurotoon-data`, schema version 1. Each bucket is a separate object store, with records keyed explicitly and timestamped:

- `catalog` — normalized or provider-sourced metadata cache.
- `library` — user-owned saved series and status/category/sort metadata.
- `progress` — per-provider, per-work, per-chapter reading positions.
- `settings` — typed-by-caller app and reader preferences.
- `repositories` — repository/source configuration metadata.
- `providerHealth` — source status and diagnostics.

Upgrades add stores without deleting existing stores. Any future schema version must use an explicit migration and preserve user-owned data. Cache eviction must operate on cache records only; it must never clear `library`, `progress`, or `settings` as a side effect.

## Reliability and privacy rules

1. Keep the first implementation local-first and no-account by default.
2. Persist user-owned data separately from disposable media/cache data.
3. Validate identifiers and normalize positions before writing; tolerate missing, malformed, quota-blocked, or unavailable storage without crashing reading.
4. Report storage capability accurately. Memory fallback keeps the app usable but cannot promise data will survive reload.
5. Do not persist comic page binaries or silently build a bulk offline archive.
6. Keep provider URLs and remote metadata attributable to their source; do not invent a cloud API or upload history.
7. Future backup/export should be user-initiated, versioned, validated, and restorable without overwriting data silently.
8. Future multi-device sync needs a separately reviewed conflict-resolution protocol and explicit user consent.

## Test coverage

The unit suite covers bucket isolation, safe storage fallback, stable source-scoped keys, library add/refresh/status/category/remove behavior, progress normalization and chapter separation, and typed settings defaults. IndexedDB migration/open-failure and end-to-end application wiring remain integration checks.
