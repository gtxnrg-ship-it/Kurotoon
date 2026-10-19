# KuroToon Roadmap

This is a living plan. Items stay **Planned** until code exists and the acceptance criteria pass. Do not report a whole phase complete because its documents exist.

## Phase 0 — Foundation and feasibility

Status: **In progress** — the PWA install path and Capacitor Android APK pipeline are merged to `main`. GitHub Actions has successfully built the `Kurotoon.apk` artifact; physical-device installation and performance checks remain open.

- [x] Establish public repository and initial documentation baseline.
- [x] Select the initial web UI stack: React + TypeScript + Vite, with Capacitor as the initial Android packaging path; validate further native requirements against device and extension feasibility.
- [x] Define type-check/production-build and unit-test commands.
- [x] Add CI checks for pull requests and main-branch pushes.
- [x] Add the PWA manifest, bounded app-shell service worker, Capacitor app identity, download UI, and CI workflow for an installable Kurotoon.apk (CI has generated a debug APK artifact; physical installation remains pending).
- [ ] Verify the generated APK by installing it on a real Android device.
- [ ] Document local setup and environment variables; commit no secrets.
- [ ] Record a baseline performance budget for mid-range Android devices.

**Exit gate:** a clean checkout can install dependencies, run checks, and build a minimal responsive shell using documented commands.

## Phase 1 — App shell and design system

Status: **In progress** — the initial procedural cosmic canvas is merged and CI-verified; physical-device performance validation remains pending.

- [ ] Establish responsive dark-first design tokens, typography, spacing, surfaces, motion, focus states, and reduced-motion support.
- [x] Add a first procedural cosmic canvas with layered colour fields, starfield, subtle large-scale filaments, pointer/touch ripples, visibility pausing, and reduced-motion handling (CI-verified; physical-device validation pending).
- [ ] Add adaptive quality settings and validate GPU/memory/battery behaviour on low-end Android hardware.
- [x] Implement the five-destination navigation shell: Home, Browser, Shop, Library, Me (full Library functionality remains a later integration task).
- [ ] Add empty, loading, error, offline, and retry states.
- [x] Add the in-app reader route and Me/settings boundary; some settings destinations remain placeholders.
- [ ] Verify narrow mobile, tablet, and desktop layouts.
- [ ] Add a first-launch cosmic reveal and shorter subsequent-launch transition only after the base renderer is profiled.
- [x] Keep source/repository management under Me/settings; the repository manager is reachable from Me settings without adding a bottom-navigation item.

**Exit gate:** navigation is keyboard/touch usable, responsive, and does not lose route state during ordinary navigation.

## Phase 2 — Domain model and provider boundary

Status: **In progress**

- [x] Define typed models for Work, Edition, ProviderListing, Chapter, ChapterListing, Creator references, ReadingProgress, LibraryEntry, and ProviderHealth.
- [x] Define source adapter contract for search, details, chapter list, and page retrieval.
- [x] Define provider capability flags, cancellation signals, and structured provider errors; request budgets/timeouts still need enforcement.
- [x] Add conservative work identity matching with confidence, reasons, and an explicit auto-merge threshold; provider-local creator IDs are not treated as globally comparable by default.
- [x] Add the first source-agnostic batch catalog engine with canonical display titles, alternate titles, source provenance, and guarded high-confidence grouping.
- [x] Add bounded potential-duplicate suggestions for review, rejecting contradictory cross-source IDs and ambiguous bridge merges.
- [x] Rank latest chapter observations by publication date, with clearly identified fallback to chapter number or source verification time.
- [ ] Persist canonical title overrides and manual identity corrections without changing stable Work/library/progress IDs.
- [ ] Expand domain tests to cover edition mapping, mini-chapters, specials, progress remapping, and provider failures.

**Exit gate:** domain logic can be tested without UI or a live provider, and source failures are distinguishable from empty results.

## Phase 3 — First real source and core reader

Status: **In progress** — the initial MangaDex series/chapter/page reader is merged to `main`. TypeScript/build, domain-test, and APK-workflow checks have passed on recent reader changes. Complete live-flow acceptance and physical-device navigation/performance verification are still pending.

- [x] Add a typed MangaDex search adapter with cancellation, timeout, explicit provider failures, and a conservative content-rating default.
- [x] Render real MangaDex search results with source attribution and honest loading/empty/error states; results can open the in-app series and chapter reader.
- [ ] Manually verify the complete live flow: search → series details → chapter list → page retrieval.
- [x] Add an initial bounded image-loading strategy: paged reading preloads the current page and immediate neighbours; vertical reading uses lazy loading and incremental page mounting. Further cancellation/concurrency hardening and device verification remain.
- [x] Save and restore per-chapter reading progress using defensive storage helpers and a saved-page anchor for vertical mode; automated tests cover malformed, missing, clamped, and unavailable storage.
- [x] Provide previous/next chapter navigation and failed-page retry UI; manually verify chapter boundaries and retry recovery on-device.
- [ ] Add durable library add/remove/status/sort and progress integration.
- [ ] Make source health and attribution consistently visible across all provider states.

**Exit gate:** verify the full search → series → reader path on old three-button Android navigation and modern gesture navigation, including retry, page/scroll restoration, chapter boundaries, and safe-area layout. A live comments service is explicitly not part of this exit gate.

## Phase 4 — Repository and extension research gate

Status: **In progress — metadata-only web proof of concept; extension compatibility is still an open research gate.**

- [x] Parse a real community repository JSON index without installing anything; parser and tests target the legacy Mihon/Tachiyomi-style JSON index shape.
- [x] Add a Me → Settings repository manager with HTTPS URL entry, supported deep-link URL extraction, local repository-list persistence, add/check/refresh/remove, metadata list filtering, and explicit error states.
- [x] Limit index responses to 15 MB and 10,000 records, reject non-HTTPS URLs, and avoid downloading or executing listed APKs.
- [ ] Add full signature/trust/package-format inspection and source permission presentation.
- [ ] Inspect package formats, host API versions, dependencies, signatures, and license notices.
- [ ] Build a disposable Android proof of concept for one extension, if licensing and technical feasibility permit.
- [ ] Verify search, details, chapters, and page URLs through the host interface.
- [ ] Document what cannot be supported in a browser/PWA.
- [ ] Decide between native compatibility, a restricted adapter bridge, and provider adapters authored for KuroToon.
- [ ] Define source permissions, provenance, update policy, rate limits, and safe failure.

**Exit gate:** a tested architecture decision with evidence. No production promise of generic Mihon/Tachiyomi compatibility before this gate passes.

## Phase 5 — Unified catalog and discovery

Status: **In progress — the first source-agnostic grouping engine exists; live multi-provider search and UI integration remain open.**

- [ ] Cross-provider search with bounded parallel requests, provider-specific limits, cancellation, and partial-result reporting.
- [ ] Local incremental search index for already-seen metadata.
- [x] Canonical display titles with retained aliases/alternate titles and source URLs.
- [x] High-confidence duplicate grouping plus bounded review suggestions; ambiguous matches are not silently merged.
- [ ] Persist the Work/Edition/listing/chapter relationships and make user corrections reversible.
- [ ] Merge equivalent chapter observations without flattening languages, adaptations, specials, mini-chapters, seasons, or doujin structure.
- [ ] Creator/artist pages with provenance.
- [ ] Explicit handling for specials, mini-chapters, seasons, and doujin structure.
- [ ] Explain partial results when a source is slow, blocked, or offline.

**Exit gate:** test fixtures prove that distinct editions are not incorrectly merged and source timeouts are not shown as “no results.”

## Phase 6 — Immersive reader and audio

Status: **Planned; staged rollout**

- [ ] Define a single reader timeline and event model.
- [ ] Add independently controlled dialogue, narration, music, ambience, and effects.
- [ ] Add safe volume defaults, global pause/mute, audio focus, and no surprise autoplay.
- [ ] Prototype OCR/bubble order/speaker labeling with confidence indicators.
- [ ] Add voice profiles and pronunciation dictionaries.
- [ ] Allow line corrections and persist user-approved corrections.
- [ ] Add optional auto-scroll and tempo controls.
- [ ] Test low-memory and interrupted-network behaviour.

**Exit gate:** basic reading works without audio; audio can be disabled instantly; timeline interruption/restart does not corrupt reading progress.

## Phase 7 — Storage, reliability, and privacy

Status: **Planned**

- [ ] Storage dashboard and cache limits.
- [ ] Separate disposable image/audio cache from durable library/progress data.
- [ ] Cleanup and recovery tests.
- [ ] Data export/backup design.
- [ ] Privacy review for history, analytics, and external speech providers.
- [ ] Diagnostics that redact tokens and personal data.
- [ ] Performance tests on slower mobile hardware.

**Exit gate:** cache cleanup cannot erase the library/progress; network and provider failures remain recoverable.

## Phase 8 — Shop / rewards

Status: **Blocked on product specification**

The destination remains in navigation, but mechanics must wait for the product owner's explanation. Do not implement guessed currency, reward loops, tasks, purchases, or monetization.

## Phase 9 — Release readiness

Status: **Planned**

- [ ] Accessibility and interaction audit.
- [ ] Security and dependency review.
- [ ] Android/PWA install and update tests.
- [ ] Reproducible production build.
- [ ] Clear release notes and known-limitations list.
- [ ] Validate all claims in README against actual behaviour.

## Working rules

1. Prefer small, reviewable pull requests with a clear acceptance gate.
2. Keep Implemented separate from Verified.
3. Add tests with domain behaviour, especially identity/progress/storage logic.
4. Do not add a dependency without a concrete reason and maintenance assessment.
5. Never put secrets, private tokens, or personal credentials in source control.
6. Revisit this roadmap when evidence or the owner's priorities change.