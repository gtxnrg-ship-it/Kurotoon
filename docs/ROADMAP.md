# Kurotoon Roadmap

> **Living, acceptance-based tracker.** These estimates are manually reviewed against merged code, tests and CI—not guessed from line count. A checkbox means the acceptance gate is met, not merely that a file exists. Update this page with every meaningful implementation milestone.

## Current checkpoint — 2026-10-21

- [x] Native Flutter/Dart application is on `main`.
- [x] Native release APK built by GitHub Actions.
- [x] Flutter static analysis and Flutter tests passed on the current main build.
- [x] Dart core CI passed on the same main commit.
- [x] APK is uploaded as `Kurotoon.apk` to a continuous development release.
- [ ] Install and verify the current APK on a real Android device.
- [x] Create and verify the stable `continuous-latest` direct-download alias; its asset exists and is downloadable.
- [ ] Install and verify the current APK on a real Android device, including the recent reader/library/repository flows.
- [ ] Run the complete search → series → chapter → read → save → resume journey against live sources on-device.
- [x] Replace the former reader/library/repository-management placeholders with working native flows; advanced settings and device acceptance remain open.

Most recent fully verified main baseline before the current library-sorting change: commit `2e086e8c95b72c623625a20a9c15963c39e0fcf6` passed CI, Dart Core and Android APK workflows. Main is now at `db9fab3a373b9efa82fdfe74f75ca5d108fa809d`; its APK and Dart Core workflows are in progress as this checkpoint is being updated. The stable `continuous-latest` alias is intended to track the latest successful main-branch build. Release assets include arm64-v8a, armeabi-v7a, x86_64 and `SHA256SUMS.txt`.

## Progress dashboard

| Workstream | Current estimate | Evidence in main | Main gaps before calling it done |
|---|---:|---|---|
| Native build and CI | 90% | Flutter APK build, analysis, tests and release workflow pass | Real-device install, package metadata/signing strategy, smoke-test automation and other platforms |
| Pure Dart domain and policy core | 70% | Typed work/edition/chapter models, cancellation, provider coordinator, identity matching, progress reconciliation, cache/effect/voice policies | More adversarial/property tests, manual identity corrections and end-to-end consumers |
| Persistent state and cache safety | 70% | SQLite schema/migrations, managed cache budget enforcement, serialized writes, pinned-content protection, rollback tests, persisted provider-health snapshots and durable library/progress operations | Migration fixtures, interrupted-write recovery and physical-device storage behaviour |
| Provider integration | 65% | Native MangaDex adapter, bounded coordination, persistent failure streaks/cooldowns, upstream `Retry-After` handling and local source diagnostics | Live flow validation, provider-specific request policies, additional source adapters and schema-drift handling |
| Repository / extension foundation | 72% | Native Me repository manager, preview/add/refresh/remove flows, JSON index/manifest checks, bounded Mihon/Tachiyomi metadata previews and persistent declarative install records | Update/rollback recovery tests, broader conformance fixtures, and compiled-extension compatibility proof |
| Cross-source catalog and chapter merge | 45% | Identity matcher, catalog index, provenance models, candidate grouping, mini-chapter/edition concepts | End-to-end persisted merge pipeline, corrections/undo, creator pages and real multi-source fixtures |
| Reader and library end-to-end | 55% | Native search-to-series-to-chapter reader, paged and long-strip reading, retry, progress resume, previous/next navigation, direction preference, Continue Reading, persisted library sorting/search, and local collection organization | Physical-device/live-source acceptance, collection migration verification, manual drag ordering, advanced fit/brightness settings and long-session reliability |
| Galaxy experience / adaptive performance | 28% | Animated Galaxy shell and persistent manual motion preference | Reduced-motion/lifecycle hardening, GPU/frame/memory/battery profiling, device-tested quality adaptation |
| Voice, music, haptics and particle runtime | 10% | Timeline/voice license and size/hash policies | Real native adapters, consent UI, stop/lifecycle integration, downloadable packs, music discovery/playback, haptic and particle tuning |
| Cross-platform releases | 10% | Shared Dart core is intended to be portable | iOS/iPadOS/Windows/Linux platform adapters, platform builds, accessibility and device test matrix |

**Engineering estimate of the full product: about 53% complete (53.4% weighted); backend foundations: roughly 71%.** These are scope estimates, not code-coverage statistics. The native reader, library and repository UI are now real and CI-tested, but live-source/physical-device acceptance, image-loading resource bounds, cross-source correction/undo, interrupted-operation recovery, adaptive performance, immersive audio/voice/haptics and other-platform builds are still significant work. Do not describe the product as release-ready until the remaining acceptance gates are recorded.

## Phase A — Native foundation and release hygiene

- [x] Establish a Flutter/Dart app entry point and a pure Dart core package.
- [x] Replace the experimental Capacitor APK path with a Flutter release build in CI.
- [x] Run Flutter analysis/tests and Dart core checks in CI.
- [x] Build and publish a downloadable APK artifact from main.
- [x] Maintain a stable `continuous-latest` APK URL in addition to immutable numbered releases.
- [ ] Add artifact checksum and build metadata to the release page and README.
- [ ] Test installation, launch, upgrade/reinstall and navigation on a physical Android device.
- [ ] Verify app label, icon, application ID, minimum Android version and signing/version policy.
- [ ] Add smoke tests for cold-start and critical navigation.
- [ ] Create reproducible release notes and a clear rollback path.

**Exit gate:** a fresh user can download a known build, install it, launch it on a tested device and report a reproducible version/commit.

## Phase B — Backend reliability and runtime integration

- [x] Keep domain rules in `packages/kurotoon_core`, independent of Flutter widgets.
- [x] Provide typed provider capability contracts and explicit structured result states.
- [x] Bound search concurrency and provider deadlines; allow cancellation.
- [x] Add first native MangaDex provider and user-toggle persistence.
- [x] Add SQLite persistence and explicit versioned schema migration.
- [x] Add repository preview-before-add, identity/URL checks and declarative manifest verification.
- [x] Store installed extension metadata and restore enabled provider state on runtime initialization.
- [ ] Test provider cancellation under real HTTP read/write stalls and ensure socket/resource disposal.
- [x] Track provider failure streaks and cooldowns, honor upstream `Retry-After`, and persist validated health snapshots without raw provider error text.
- [x] Surface provider health and cooldowns in a local diagnostics screen under Me without issuing diagnostic network requests or displaying raw errors.
- [ ] Define provider-specific request policies and a redacted diagnostic export.
- [ ] Exercise every SQLite migration from a real previous-version database fixture.
- [ ] Test app kill/crash during extension install/update/uninstall and recover orphan temp files safely.
- [ ] Add a structured diagnostic export that redacts credentials, tokens and private user data.
- [x] Enforce storage budget on managed cache writes with serialized operations, pinned-content protection and staged rollback if SQLite metadata commit fails.
- [ ] Add cache dry-run/metrics surfaces and recover interrupted cache writes after process death.
- [ ] Add backup/export only with versioned schema, preview, validation and explicit user confirmation.

**Exit gate:** interrupted network, source failure, app restart and storage failure never corrupt user-owned data or masquerade as a successful empty response.

## Phase C — Repository and provider ecosystem

- [x] Define repository and extension index/manifest models.
- [x] Support explicit preview and confirmation API, manual HTTPS URL input and deep-link parsing.
- [x] Use declarative manifests rather than arbitrary downloaded code execution.
- [x] Validate index-declared manifest size/hash and cross-check identity/version/capabilities.
- [x] Build Me → Extensions & repositories UI with manual URL input, preview, add, refresh, remove, extension enable/disable/uninstall and error/retry states.
- [ ] Add clearer per-extension permission/trust summaries and update/rollback recovery.
- [ ] Add extension listing, detail/capability/host/license display, explicit install/update/uninstall and enabled switch.
- [ ] Support multiple repo catalogs, collision handling, repo attribution and stale-index UX.
- [ ] Add update preview with version/digest diff and rollback to last valid manifest.
- [ ] Build conformance fixtures for allowed/disallowed URLs, DNS, IPv4/IPv6, redirect, oversized body, malformed JSON, hash mismatch, stale preview and changed repository identity.
- [ ] Investigate Mihon/Tachiyomi APK compatibility independently; do not claim support without a working Android host/API proof of concept.
- [ ] Add more real native provider adapters (candidate examples: Webtoon, Tapas, and other sources) only with lawful, stable APIs and source-specific terms respected.

**Exit gate:** users can safely add several repositories, inspect before trusting, install one declarative source, update/disable/remove it and recover from broken metadata.

## Phase D — Universal catalog and reading data

- [x] Define Work / Edition / provider listing / Chapter / chapter listing / creator-credit concepts.
- [x] Preserve provider provenance and source-specific identity.
- [x] Add conservative identity matching and explicit review candidates.
- [x] Model mini-chapter groups, reading-progress reconciliation and creator-work capability.
- [ ] Persist approved merges, user corrections and undo without changing stable user/library IDs.
- [ ] Build a multi-source synchronization pipeline with bounded concurrent fetches and conflict records.
- [ ] Track translations, release groups, language, source timestamps and the last verified chapter per source.
- [ ] Keep special chapters, seasons, one-shots, doujin layouts and mini-chapters distinct and correctly counted.
- [ ] Build creator/artist pages aggregating all source editions with evidence and alternate identities.
- [x] Add durable library operations for membership, status, filtering and persistent sorting (recent activity, recently added, A–Z, Z–A).
- [ ] Add manual drag ordering and custom categories across the library and collections.
- [ ] Verify named local collections on-device and after process restart, including schema migration and preserving saved progress when collections or memberships are removed.
- [ ] Add library update notifications without duplicate spam and with source disable/mute controls.
- [ ] Add import/export for library and progress with identity review, dry-run and conflict handling.

**Exit gate:** the same work across multiple sources appears once when evidence is strong, distinct adaptations remain distinct, and removing a provider never deletes the user's library/progress.

## Phase E — Native reader vertical slice

- [x] Implement native Flutter series details, chapter selection and chapter reader; no WebView wrapper.
- [ ] Complete physical-device and live-source acceptance for the full reading journey.
- [x] Display manga/manhwa/webtoon content with builder-backed continuous long-strip mode and paged reading.
- [ ] Bound image decode/prefetch concurrency and bytes; cancel previous chapter work on navigation.
- [x] Add page retry, loading/failure states, broken-page recovery and a selectable reader source where multiple chapter providers are available.
- [x] Persist page-based reading progress and restore the saved chapter/page when it remains in the stored chapter list.
- [ ] Coalesce high-frequency progress writes and prove correct resume on varied long-strip image aspect ratios.
- [x] Implement previous/next chapter controls and honest chapter-boundary feedback.
- [ ] Verify safe areas and swipe/gesture behavior across three-button and gesture navigation on physical devices.
- [x] Add persistent reading direction (RTL/LTR), paged/long-strip layout and data-saver controls.
- [ ] Add fit/scale, brightness where supported and page-gap settings.
- [ ] Ensure external links and unsafe source responses cannot break navigation or escape a safe scheme policy.
- [ ] Test with slow/error networks, very long webtoons, huge image dimensions, malformed media types and app background/foreground transitions.

**Exit gate:** a user can search MangaDex, open series, choose a chapter, read it, retry failed pages, change chapters, close/reopen the app and resume at the expected position.

## Phase F — Galaxy UI and platform polish

- [x] Add an initial native Galaxy backdrop and five-tab navigation shell.
- [ ] Define reusable tokens for surfaces, contrast, typography, spacing, focus, haptics and motion.
- [ ] Add reduced-motion support and pause animations when hidden/backgrounded.
- [ ] Keep the galaxy behind content, never underneath text with insufficient contrast or over manga pages by default.
- [ ] Add adaptive particle/star counts and effects quality that degrade under frame-time pressure.
- [ ] Avoid rebuild storms, unbounded animation controllers, per-frame allocations and excess blur over large screen areas.
- [ ] Profile cold start, scroll frame pacing, image-heavy browsing, memory, battery and thermal behaviour on low-end and mid-range devices.
- [ ] Verify phone/tablet/desktop breakpoints, keyboard, screen reader, large text and Android navigation modes.
- [ ] Replace placeholders with genuine loading, empty, failure, retry and offline experiences.
- [x] Implement a native Library with membership, status, resume, filtering and sorting; keep Shop isolated until its rules are defined.

**Exit gate:** core reading remains smooth, accessible and fully usable with all Galaxy effects disabled.

## Phase G — Optional immersive layer

- [x] Define chapter-relative cue models/policies and voice-pack license/size/hash constraints.
- [ ] Wire haptics through an injected native adapter with system preference checks.
- [ ] Build an optional native audio timeline that respects focus, mute, backgrounding and reader lifecycle.
- [ ] Build voice-pack discovery/download/install/remove with license, digest, size, free-space and cancellation gates.
- [ ] Keep OCR/speaker/emotion/dialogue detection explicitly uncertain, correctable and off by default until accuracy is evaluated.
- [ ] Build the browser-native atmospheric music discovery engine with explicit source attribution and user-initiated playback.
- [ ] Add particle/effect budgets, reduced-motion handling, quality controls and a global effects kill switch.
- [ ] Test no audio/effects mode and ensure reading does not depend on downloaded voice packs.
- [ ] Measure incremental CPU, memory, startup, battery and storage cost for each optional feature.

**Exit gate:** immersive features are opt-in, reversible, measurable and never a dependency of ordinary reading.

## Phase H — Cross-platform and final acceptance

- [ ] Define and build iOS/iPadOS host integration with the same Flutter/Dart domain rules.
- [ ] Add Windows/Linux desktop launch/build workflows where platform dependencies permit.
- [ ] Validate persistence, audio session, files, haptics, lifecycle and reader gestures per platform.
- [ ] Add an accessibility pass and security/threat-model review.
- [ ] Publish a stable release channel, versioned releases, checksums and user-visible change notes.
- [ ] Establish a tested support matrix, minimum OS versions and known-limitations section.

**Exit gate:** supported platforms have reproducible builds and documented test evidence, not only shared source code.

## Rules for progressing the percentage

1. Change a checkbox only when its evidence is available in code/tests or a recorded manual test.
2. A schema or policy type is foundation work; it does not count as a user-facing feature until integrated and exercised.
3. CI green does not imply live-source compatibility or physical-device acceptance.
4. Recalculate the dashboard when a substantial milestone merges, and record what evidence changed the estimate.
5. Keep blocked items visible instead of silently removing them to improve the number.
