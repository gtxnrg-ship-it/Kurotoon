# Kurotoon Architecture

> **Status: accepted direction.** The active Android app is Flutter/Dart. This document supersedes older web-first and Capacitor-first proposals. The production APK must be built from `apps/kurotoon_flutter`; it must not be a website wrapped in a WebView.

## Architecture at a glance

```text
Flutter screens and navigation
        |
Application runtime / services
        |
Pure Dart domain package (packages/kurotoon_core)
        |
        +-- provider contracts + bounded coordinator
        +-- cross-source identity/catalog policies
        +-- reading-progress reconciliation
        +-- repository/manifest safety policies
        +-- cache/effects/voice-pack policies
        |
Platform adapters
        +-- SQLite (sqflite) for durable app-owned records
        +-- native HTTP client with cancellation and response caps
        +-- managed files for optional media/cache
        +-- future native audio, speech, haptics, lifecycle adapters
```

The core package must remain unit-testable without Flutter widgets, a live network, or physical hardware. Widgets orchestrate interactions; they do not own catalog matching, request limits, persistence schemas, or repository trust rules.

## Current implementation

- `packages/kurotoon_core` defines the shared domain contracts and deterministic policy layer.
- `apps/kurotoon_flutter` is the current Android application entry point and runtime composition root.
- SQLite schema version 2 stores catalog identities/listings, editions, chapter/source listings, library entries, progress, settings, creator credits, identity-review suggestions, bounded-cache metadata, voice-pack installs, repositories, and installed declarative extensions.
- The repository service previews an index before confirmation, checks index/manifest identity, verifies package size and SHA-256, caps response bodies, rejects redirects, uses timeouts/cancellation, and checks DNS results before requests.
- GitHub Actions runs Flutter analysis/tests and produces a native release APK. The first APK build is CI-verified; physical-device behaviour remains unverified.
- The current Flutter screen tree is a shell with live search. A complete native reader/library/repository-management experience is not yet integrated.

## Product/platform commitments

1. **Native-first:** Flutter/Dart is the shared application UI and domain stack; native platform APIs live behind adapters. Do not restore Capacitor as the Android app runtime without an explicit product-owner decision.
2. **Primary navigation stays:** Home, Browser, Shop, Library, Me. The reader is a dedicated route. Repositories and extensions live under Me/settings, not as a sixth bottom-tab item.
3. **Galaxy identity:** dark cosmic background, slow layered colour fields, stars/particles, soft depth/glow, restrained motion and context-aware transitions. The theme must remain readable; effects can never obscure comic pages or primary controls.
4. **Performance is a budget:** target smooth 60 FPS on ordinary devices, degrade effects under load, pause animation while backgrounded, respect reduced-motion settings, bound image/request concurrency, virtualize long lists, and dispose controllers. These are acceptance goals until measured on physical devices.
5. **Live-first storage:** default to live provider fetches and bounded disposable cache. The initial cache planner defaults to 1.5 GiB. Never evict the user's library, settings, reading progress, pinned offline content, or other user-owned data as if it were cache.
6. **Local-first privacy:** no remote application server or account sync is implemented. Reading history and library data stay on-device unless a separately reviewed, explicit export/sync feature is added.
7. **Honest source behaviour:** keep provider attribution, preserve source-specific IDs/URLs, report blocked/timeout/malformed/partial results separately from empty results, and never retry indefinitely.

## Provider contract and request safety

Providers expose capabilities for search and, where supported, work details, chapter feeds, creator works and reader pages. Requests must carry cancellation, a bounded deadline and response-size limits. Provider failures are typed states; a failed source must not be represented as a valid empty catalogue.

The coordinator bounds active provider calls. Production HTTP adapters must propagate cancellation into the underlying socket/request, apply per-host concurrency and respectful request pacing, reject unsafe URLs/redirects, cap response bodies before JSON parsing, and keep diagnostics scrubbed of credentials. Do not make repeated retries that can overload community sources or trigger IP bans.

### MangaDex

MangaDex is the initial built-in/live source. It can be disabled by the user and must not be removable through the community-extension uninstall path. Its presence must not hard-code the rest of the app to MangaDex IDs or schemas.

### Community extension boundary

The supported first extension format is **declarative JSON**, not arbitrary downloaded Dart, Java/Kotlin, APK or JavaScript execution. A repository index lists packages; adding a repository must not download every extension. The user reviews repository identity, sees capabilities/source attribution and explicitly chooses an extension to install.

Validate HTTPS, credentials, ports/fragments, local/private IP literals and resolved addresses; do not follow redirects; enforce bounded index/manifest/data sizes; verify index-declared manifest SHA-256/byte size and matching version, ID and capabilities. A URL string check alone is not a complete SSRF defence. Future redirect support must re-validate every destination and resolve/pin addresses safely. Native Mihon/Tachiyomi APK compatibility remains a separate research gate; downloading an APK/index does not make it executable.

## Cross-source identity and chapter model

Do not equate a provider listing URL with a global work ID. Keep these concepts separate:

- **Work:** the underlying series, one-shot or story.
- **Edition:** a language, adaptation, season/edition or meaningful publication variant.
- **Provider listing:** one source's version of a work/edition, including its own identifiers, title, URL and metadata provenance.
- **Chapter:** a logical chapter only when evidence supports the relationship.
- **Chapter listing:** a source-specific release/translation of that chapter.
- **Creator/credit:** person or credited entity plus role and source evidence.
- **Identity review:** low-confidence possible duplicates that require review rather than silent merges.

Title similarity is not sufficient for automatic merge. Contradictory year, format, language, edition or source identifiers should lower confidence or veto a link. Preserve alternate titles, original source fields, provider IDs and the reasoning behind a suggestion. Chapter count must explain specials, seasons and mini-chapter bundles; six mini-chapters should not silently become six ordinary full chapters. Latest translation/source selection must retain source and language provenance.

## Durable state and storage

SQLite migrations are append-only and versioned. Every migration must preserve user data and be covered by tests. User-owned library/progress/preferences and identity corrections are distinct from disposable provider responses, covers, page previews, audio, and voice model cache.

- Keep large media files out of SQLite; store their managed paths and byte counts.
- Cache eviction must use an explicit plan and execute only against cache rows/files; protect pinned offline content.
- Clean up partially written files on failed/cancelled installs.
- Avoid blocking the UI isolate with big JSON transformations, disk scans, image decoding, or bulk migrations.
- Report when persistence is unavailable; do not pretend in-memory fallback is durable.
- Backup/export and multi-device sync are future features. They need versioned formats, validation, restore preview and conflict handling before implementation.

## Reader timeline, voice, sound, haptics and particles

The domain layer may describe chapter-relative cues and policies, but that is not proof a native effect is wired up. All channels are opt-in, independently adjustable, and easy to mute/stop. Reader-page rendering is the primary priority; effects may never delay or block it.

- The reader must work fully in silent, reduced-motion, offline/blocked-source and no-voice-pack modes.
- Speech/translation/OCR/speaker/emotion decisions are uncertain metadata. Never present inferred dialogue as ground truth; keep confidence and user corrections.
- Voice packs require license, size and SHA-256 validation; downloads must be explicit and cancellable.
- Audio must obey platform focus/lifecycle, avoid unexpected autoplay and stop when the reader closes or the app backgrounds.
- Haptics must respect system settings and never fire for every trivial scroll event.
- Particles need adaptive quality and a kill switch, with bounded controllers and no per-frame allocations on the hot path where avoidable.
- A browser-native atmospheric music discovery/player engine is a future feature; it must not extract/play arbitrary media without clear user control and a safe playback contract.

## Performance and acceptance gates

Targets are goals, not current measured results:

- 60 FPS target on mid-range hardware; stable usable fallback on lower-end Android.
- No synchronous network or expensive disk work on the UI isolate.
- Bound concurrent sources, page prefetch, decode queue, request/response bytes, caches, and extension limits.
- Pause expensive motion when not visible/backgrounded; respect reduced motion.
- Measure cold start, search latency, first reader-page render, scrolling frame pacing, peak memory, cache growth and battery impact on real devices.
- Test narrow phones, tablets and desktop layouts; Android three-button and gesture navigation; safe areas; large text; keyboard and screen-reader navigation.
- CI success is necessary but not a substitute for device testing, live-source verification, security review or accessibility checks.

## Change rules for future agents

Before changing architecture, read `README.md`, `docs/PRODUCT_VISION.md`, `docs/ROADMAP.md`, `docs/DECISIONS.md`, and `docs/EXTENSION_REPOSITORIES.md`.

1. Keep the root README's project name as `# Kurotoon`.
2. Update the roadmap/status when a feature changes state; mark complete only when acceptance criteria pass.
3. Add tests with policy or domain changes, and add migration tests when schema changes.
4. Do not replace the native APK workflow with a WebView/Capacitor build.
5. Do not claim voice, haptics, particles, cross-device sync, universal extension compatibility or physical-device performance until integrated and tested.
6. Do not silently discard user data, bypass source restrictions, or broaden repository trust.
7. Keep Shop mechanics reserved until the product owner defines them.
