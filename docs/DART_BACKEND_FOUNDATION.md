# Kurotoon Dart backend foundation

**Status: active foundation; not production-complete.** The native product direction is Flutter/Dart. The Android APK is built from `apps/kurotoon_flutter`; the domain/policy layer lives in `packages/kurotoon_core`. The legacy React/TypeScript prototype may remain in the repository for reference, but it is not the active Android application and must not be wrapped in Capacitor as a substitute for the native Flutter app.

## Workspace boundaries

- `packages/kurotoon_core`: platform-independent models and deterministic rules for catalog identity, chapter grouping, provider coordination, cancellation, progress reconciliation, repository/manifest policy, storage budget planning, reader timeline cues, experience/effect budgets and voice-pack eligibility.
- `apps/kurotoon_flutter`: Flutter UI, composition root, native application runtime, SQLite persistence and HTTP-backed repository/extension services.
- `.github/workflows/dart-core.yml`: formatting/static analysis/unit tests for the core.
- `.github/workflows/android-apk.yml`: Flutter analysis/tests, native Android release APK build, artifact upload and development-release publication.

The shared code is not a remote server. Current backend means device-side domain rules, persistence and provider services. There is no hosted account, cloud sync or application API today.

## Backend invariants

- Cross-source matching preserves provenance; title similarity alone must not automatically merge works. Contradictory year, format, language, edition or source identifiers lower confidence or veto automatic matching; uncertain candidates remain reviewable.
- Provider search has bounded concurrency, a request deadline, cancellation and explicit partial/blocked/rate-limited/timeout/malformed states. A failure must not masquerade as an empty source.
- MangaDex is a built-in/live source that the user can disable. It cannot be removed through the community-extension uninstall path.
- Repository indexes and extension manifests are declarative JSON, not executable code. Repository addition requires preview/review and confirmation; installation is opt-in per extension.
- Repository traffic must use HTTPS, reject embedded credentials/custom ports/fragments and local/private addresses, validate resolved IPs, reject redirects, cap response/index/manifest sizes, set timeouts, propagate cancellation and verify manifest integrity against index metadata. This is defense in depth, not a guarantee against every platform/network DNS race; keep the security limitation documented and tested.
- Reading progress uses deterministic timestamp/revision reconciliation while allowing an intentional newer rewind.
- The cache planner defaults to 1.5 GiB for disposable cache-managed assets, not total app data. Eviction may only affect explicitly classified cache entries; pinned/offline user data and library/progress/preferences must be protected.
- Reader cues share a chapter-relative timeline. Voice, sound, haptics and particles are optional; inferred dialogue is uncertain and separately gated. Policy models do not prove the native adapters exist.
- Platform adapters must provide actual storage, network cancellation, audio focus/lifecycle, speech, haptics and file operations. Do not create fake no-op implementations that the UI reports as success.

## Current integrated services

- Runtime composition registers the built-in MangaDex adapter, restores persisted provider enablement, and loads installed declarative extension manifests from app-private storage.
- SQLite schema version 2 persists normalized listing/catalog records, library/progress/settings, creator credits, review candidates, cache metadata, voice-pack install metadata, extension repositories and installed extensions.
- Repository service offers preview-before-add, index refresh/identity checks, declared size/SHA-256 verification, safe install file creation and cancellation-aware HTTP fetches.
- CI has built a native Flutter APK and passed Flutter analysis/tests and Dart core checks on main.
- Native Flutter UI is still an initial shell. Full chapter-reader navigation, library workflows and the repository manager are not yet fully surfaced end-to-end. Physical-device verification remains open.

## Verification required before production

1. Unit tests for every policy boundary and malformed input; no reliance on the UI to enforce a security invariant.
2. Migration tests starting from each supported old schema and preserving real records.
3. Integration tests for HTTP cancellation, stalled bodies, oversized chunked bodies, redirects, DNS edge cases, stale repository previews, digest mismatches and update rollback.
4. Recovery tests for interrupted installs/uninstalls and orphan temporary files.
5. Runtime tests that exercise provider settings, source failures, library/progress flows and cache plans through the same composition root the UI uses.
6. Physical-device tests for app lifecycle, cold start, image decoding/reader behaviour, voice/audio focus, haptics, frame pacing, memory and battery.
7. A diagnostic export that removes URLs with credentials, auth values, personal data and any future tokens before logs leave the device.

Do not claim the backend is "finished" based on schemas and models alone. Production readiness requires each capability to be wired through runtime, tests, UI and failure recovery, with device evidence where it depends on a platform API.
