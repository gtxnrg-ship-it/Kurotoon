# Kurotoon Roadmap

> **Living, acceptance-based tracker.** These estimates are manually reviewed against merged code, tests and CI—not guessed from line count. A checkbox means the acceptance gate is met, not merely that a file exists. Update this page with every meaningful implementation milestone.

## Current checkpoint — 2026-10-19

- [x] Native Flutter/Dart application is on `main`.
- [x] Native release APK built by GitHub Actions.
- [x] Flutter static analysis and Flutter tests passed on the current main build.
- [x] Dart core CI passed on the same main commit.
- [x] APK is uploaded as `Kurotoon.apk` to a continuous development release.
- [ ] Install and verify the current APK on a real Android device.
- [x] Create and verify the stable `continuous-latest` direct-download alias; its asset exists and is downloadable.
- [ ] Run the native product flows against live sources on-device.
- [ ] Replace incomplete screen placeholders with the real reader, library and repository-management flows.

Last verified APK build: commit `26b46e485882598f6329eadcd3844e5d146fffa7`; stable alias: `continuous-latest`. That release contains an arm64-v8a default APK, separate armeabi-v7a and x86_64 builds, and `SHA256SUMS.txt`. Verified voice-pack storage merged at `32acd832c55ec41fe5781e1639445e6938075bc0`; its APK rebuild is running, and the direct link will update after the next successful main build.

## Progress dashboard

| Workstream | Current estimate | Evidence in main | Main gaps before calling it done |
|---|---:|---|---|
| Native build and CI | 90% | Flutter APK build, analysis, tests and release workflow pass | Real-device install, package metadata/signing strategy, smoke-test automation and other platforms |
| Pure Dart domain and policy core | 70% | Typed work/edition/chapter models, cancellation, provider coordinator, identity matching, progress reconciliation, cache/effect/voice policies | More adversarial/property tests, manual identity corrections and end-to-end consumers |
| Persistent state and cache safety | 65% | SQLite schema/migrations, cache-budget enforcement, pinned-content protection, rollback tests, persisted provider-health snapshots and verified voice-pack install records | Verify complete CRUD integration, interrupted-write recovery and physical-device storage behaviour |
| Provider integration | 58% | Native MangaDex adapter, bounded coordination, persistent failure streaks/cooldowns and upstream `Retry-After` handling | Live flow validation, provider-specific request policies, diagnostics UI, more source adapters and schema-drift handling |
| Repository / extension foundation | 65% | Preview/confirmation API, index/manifest checks, hashes/size caps, redirect rejection, DNS checks, persistent install records | Real repository UI, source permissions and compatibility display, update/uninstall recovery tests, deeper DNS pinning review |
| Cross-source catalog and chapter merge | 45% | Identity matcher, catalog index, provenance models, candidate grouping, mini-chapter/edition concepts | End-to-end persisted merge pipeline, corrections/undo, creator pages and real multi-source fixtures |
| Reader and library end-to-end | 20% | Core models/persistence foundation and previous product prototype evidence | Flutter-native reader, chapters/pages, progress resume, durable library CRUD, sorting, empty/error/offline states |
| Galaxy experience / adaptive performance | 25% | Initial animated Galaxy shell and effect-budget policy | Reduced-motion/lifecycle hardening, GPU/frame/memory/battery profiling, device-tested quality adaptation |
| Voice, music, haptics and particle runtime | 18% | Timeline/policy foundation plus verified voice-pack storage, offline reuse and safe uninstall | Voice-pack UI/playback, music discovery, native haptics, particle controls and device tests |
| Cross-platform releases | 10% | Shared Dart core is intended to be portable | iOS/iPadOS/Windows/Linux platform adapters, platform builds, accessibility and device test matrix |

**Engineering estimate of the full product: about 43% complete.** This is a practical scope estimate, not an objective code-coverage statistic. The native build foundation is real and CI-verified; the product is not finished because the real reader, library, repository UI, cross-source integration, effects, and device acceptance are still major work. The separate backend-foundation estimate is roughly 66–68%; a larger portion of the foundations exists than is wired into an end-to-end user experience.

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
- [ ] Surface provider health in diagnostics/settings UI and encode provider-specific request policies.
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
- [ ] Build Me → Settings → Repositories UI with loading, trust warning, preview, add, refresh, remove and retry.
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
- [ ] Add durable library operations: add/remove, status, manual ordering, custom collections, sort and filter.
- [ ] Add library update notifications without duplicate spam and with source disable/mute controls.
- [ ] Add import/export for library and progress with identity review, dry-run and conflict handling.

**Exit gate:** the same work across multiple sources appears once when evidence is strong, distinct adaptations remain distinct, and removing a provider never deletes the user's library/progress.

## Phase E — Native reader vertical slice

- [ ] Implement chapter selection and chapter reader in Flutter; no WebView wrapper.
- [ ] Display manga/manhwa/webtoon page types with long-strip virtualization and predictable paging.
- [ ] Bound image decode/prefetch concurrency and bytes; cancel previous chapter work on navigation.
- [ ] Add page retry, network states, broken-page recovery and source attribution.
- [ ] Persist reading progress continuously but with write coalescing; restore the correct page/anchor on reopen.
- [ ] Implement previous/next chapter navigation, chapter boundaries, safe-area handling and gestures.
- [ ] Add reader settings: reading direction/layout, fit/scale, brightness where platform allows, page gap and data saver.
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
- [ ] Implement Library after persistence API and Reader acceptance gates; keep Shop isolated until its rules are defined.

**Exit gate:** core reading remains smooth, accessible and fully usable with all Galaxy effects disabled.

## Phase G — Optional immersive layer

- [x] Define chapter-relative cue models/policies and voice-pack license/size/hash constraints.
- [ ] Wire haptics through an injected native adapter with system preference checks.
- [ ] Build an optional native audio timeline that respects focus, mute, backgrounding and reader lifecycle.
- [x] Implement verified voice-pack storage with opt-in, license/digest/size/free-space gates, streaming SHA-256 verification, safe paths, offline reuse and uninstall safety.
- [ ] Wire voice-pack discovery/progress/cancel UI and playback into the reader timeline; add end-to-end HTTPS and physical-device tests.
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
